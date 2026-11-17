import { ManagedIdentityCredential } from '@azure/identity'
import { performance } from 'node:perf_hooks'
import sql from 'mssql'

const server = requireEnv('AZURE_SQL_SERVER')
const database = requireEnv('AZURE_SQL_DATABASE')
const sqlScope = 'https://database.windows.net/.default'

// A paused Hyperscale serverless database rejects logins until the resume completes.
const resumeErrorCodes = new Set([40613, 40197, 40501, 49918, 49919, 49920, 4060, 18456])
const maxConnectAttempts = 30
const connectRetryDelayMs = 10_000
const resumeThresholdMs = 5_000

const searchSql = `
DECLARE @QueryVector VECTOR(512) = CAST(@queryVectorJson AS VECTOR(512));

WITH VectorRaw AS
(
  SELECT TOP (25) WITH APPROXIMATE
         chunk.document_id, chunk.chunk_number, vector_result.distance AS Distance
  FROM VECTOR_SEARCH
  (
      TABLE = dbo.pmc_chunks AS chunk,
      COLUMN = embedding,
      SIMILAR_TO = @QueryVector,
      METRIC = 'COSINE'
  ) AS vector_result
  WHERE chunk.is_boilerplate = 0
  ORDER BY vector_result.distance
),
BestPerDocument AS
(
  SELECT document_id, chunk_number, Distance,
         ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY Distance) AS DocumentRank
  FROM VectorRaw
)
SELECT TOP (5)
  CONCAT('PMC', document.pmcid) AS PmcId,
  best.chunk_number,
  best.Distance
FROM BestPerDocument AS best
INNER JOIN dbo.pmc_documents AS document
    ON document.document_id = best.document_id
WHERE best.DocumentRank = 1
ORDER BY best.Distance;`

const sampleVectorsSql = `
SELECT TOP (@sampleSize) CAST(chunk.embedding AS NVARCHAR(MAX)) AS EmbeddingJson
FROM dbo.pmc_chunks AS chunk
WHERE chunk.is_boilerplate = 0
ORDER BY NEWID();`

const insertRunSql = `
INSERT dbo.CaldovaWorkloadRun
(
  StartedAtUtc, Intensity, ConnectAttempts, ConnectMilliseconds, ResumeObserved,
  QueryCount, Concurrency, MedianQueryMilliseconds, P95QueryMilliseconds,
  TotalMilliseconds, FailedQueries
)
VALUES
(
  @startedAtUtc, @intensity, @connectAttempts, @connectMilliseconds, @resumeObserved,
  @queryCount, @concurrency, @medianQueryMilliseconds, @p95QueryMilliseconds,
  @totalMilliseconds, @failedQueries
);`

function requireEnv(name) {
  const value = process.env[name]?.trim()
  if (!value) throw new Error(`${name} is not configured`)
  return value
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

// Intensity varies by hour so the 14-day window exercises the full 0.5-2 vCore range.
function planFor(date) {
  const hour = date.getUTCHours()
  if (hour % 12 === 0) return { intensity: 'heavy', queryCount: 240, concurrency: 8 }
  if (hour % 6 === 0) return { intensity: 'medium', queryCount: 90, concurrency: 4 }
  return { intensity: 'light', queryCount: 30, concurrency: 2 }
}

function percentile(values, fraction) {
  if (values.length === 0) return 0
  const sorted = [...values].sort((left, right) => left - right)
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(fraction * sorted.length) - 1))
  return Math.round(sorted[index])
}

async function connectWithResume(credential) {
  const started = performance.now()
  let attempts = 0
  let lastError

  while (attempts < maxConnectAttempts) {
    attempts += 1
    try {
      const accessToken = await credential.getToken(sqlScope)
      if (!accessToken) throw new Error('Managed identity did not return an Azure SQL access token')
      const pool = await new sql.ConnectionPool({
        server,
        database,
        authentication: {
          type: 'azure-active-directory-access-token',
          options: { token: accessToken.token },
        },
        options: { encrypt: true, trustServerCertificate: false, enableArithAbort: true },
        connectionTimeout: 60_000,
        requestTimeout: 120_000,
        pool: { min: 0, max: 10, idleTimeoutMillis: 30_000 },
      }).connect()
      await pool.request().query('SELECT 1 AS Ready;')
      return { pool, attempts, connectMilliseconds: Math.round(performance.now() - started) }
    } catch (error) {
      lastError = error
      const code = Number(error?.number ?? error?.code)
      const retryable = resumeErrorCodes.has(code) || /not currently available|paused|resum/i.test(String(error?.message))
      console.log(JSON.stringify({
        event: 'connect-retry',
        attempt: attempts,
        code: Number.isFinite(code) ? code : null,
        retryable,
        message: String(error?.message ?? error).slice(0, 300),
      }))
      if (!retryable && attempts >= 3) break
      await delay(connectRetryDelayMs)
    }
  }
  throw lastError ?? new Error('Could not connect to the research database')
}

async function loadQueryVectors(pool, sampleSize) {
  const sampled = await pool.request().input('sampleSize', sql.Int, sampleSize).query(sampleVectorsSql)
  const vectors = sampled.recordset
    .map((row) => row.EmbeddingJson)
    .filter((value) => typeof value === 'string')
  if (vectors.length === 0) throw new Error('No query vectors are available')
  return vectors
}

async function runBurst(pool, vectors, plan) {
  const durations = []
  let failedQueries = 0
  let issued = 0

  async function worker() {
    while (true) {
      const index = issued
      if (index >= plan.queryCount) return
      issued += 1
      const vectorJson = vectors[index % vectors.length]
      const started = performance.now()
      try {
        await pool.request().input('queryVectorJson', sql.NVarChar(sql.MAX), vectorJson).query(searchSql)
        durations.push(performance.now() - started)
      } catch (error) {
        failedQueries += 1
        console.log(JSON.stringify({ event: 'query-failed', message: String(error?.message ?? error).slice(0, 300) }))
      }
    }
  }

  await Promise.all(Array.from({ length: plan.concurrency }, worker))
  return { durations, failedQueries }
}

async function main() {
  const startedAt = new Date()
  const plan = planFor(startedAt)
  const totalStarted = performance.now()

  const credential = new ManagedIdentityCredential(
    process.env.AZURE_CLIENT_ID?.trim() ? { clientId: process.env.AZURE_CLIENT_ID.trim() } : {},
  )
  const { pool, attempts, connectMilliseconds } = await connectWithResume(credential)
  const resumeObserved = connectMilliseconds > resumeThresholdMs || attempts > 1

  try {
    const vectors = await loadQueryVectors(pool, 25)
    const { durations, failedQueries } = await runBurst(pool, vectors, plan)
    const totalMilliseconds = Math.round(performance.now() - totalStarted)
    const summary = {
      event: 'workload-run',
      startedAtUtc: startedAt.toISOString(),
      intensity: plan.intensity,
      connectAttempts: attempts,
      connectMilliseconds,
      resumeObserved,
      queryCount: plan.queryCount,
      concurrency: plan.concurrency,
      succeededQueries: durations.length,
      failedQueries,
      medianQueryMilliseconds: percentile(durations, 0.5),
      p95QueryMilliseconds: percentile(durations, 0.95),
      totalMilliseconds,
    }

    await pool.request()
      .input('startedAtUtc', sql.DateTime2(0), startedAt)
      .input('intensity', sql.VarChar(16), plan.intensity)
      .input('connectAttempts', sql.Int, attempts)
      .input('connectMilliseconds', sql.Int, connectMilliseconds)
      .input('resumeObserved', sql.Bit, resumeObserved)
      .input('queryCount', sql.Int, plan.queryCount)
      .input('concurrency', sql.Int, plan.concurrency)
      .input('medianQueryMilliseconds', sql.Int, summary.medianQueryMilliseconds)
      .input('p95QueryMilliseconds', sql.Int, summary.p95QueryMilliseconds)
      .input('totalMilliseconds', sql.Int, totalMilliseconds)
      .input('failedQueries', sql.Int, failedQueries)
      .query(insertRunSql)

    console.log(JSON.stringify(summary))
  } finally {
    await pool.close()
  }
}

main().catch((error) => {
  console.error(JSON.stringify({ event: 'workload-failed', message: String(error?.message ?? error) }))
  process.exitCode = 1
})

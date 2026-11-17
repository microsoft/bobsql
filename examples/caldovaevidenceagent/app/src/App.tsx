import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import {
  ArrowUpRight,
  Bot,
  BookOpen,
  Check,
  ChevronDown,
  Clock3,
  FileText,
  Search,
  Sparkles,
} from 'lucide-react'
import './App.css'
import AgentWorkspace from './AgentWorkspace.tsx'

// Empty when the API is served from the same origin; set when the UI is hosted by Fabric.
const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '')

type Environment = 'small' | 'million' | 'replica'
type SearchMode = 'vector' | 'keyword' | 'hybrid'
type ResultView = 'evidence' | 'sql'
type Workspace = 'evidence' | 'agent'

type Evidence = {
  documentId: string
  title: string
  chunkNumber: number
  distance: number | null
  passage: string
  previousPassage: string | null
  nextPassage: string | null
}

type SearchResponse = {
  environment: Environment
  databaseLabel: string
  tableName: string
  mode: SearchMode
  chunkCount: number
  documentCount: number
  indexStatus: string
  embedMs: number
  vectorSearchMs: number | null
  databaseMs: number
  totalMs: number
  evidence: Evidence[]
}

type ReadinessResponse = {
  environment: Environment
  databaseLabel: string
  tableName: string
  configured: boolean
  reachable: boolean
  indexReady: boolean
  keywordReady: boolean
  chunkCount: number | null
  documentCount: number | null
  ready: boolean
  message: string
}

const DEMO_QUERIES = [
  'What biological mechanisms connect periodontal inflammation with elevated blood pressure and cardiovascular risk?',
  'Does treatment of chronic inflammatory disease reduce the subsequent risk of cardiovascular events?',
  'How does disruption of the intestinal microbiome influence anxiety and depressive symptoms?',
  'Can physical activity slow functional and cognitive deterioration in people with neurodegenerative disease?',
  'Why do some cancer patients fail to respond to immune-based treatment despite initially showing tumor regression?',
]

const SEARCH_SQL = `DECLARE @QueryVector VECTOR(512) =
  CAST(@queryVectorJson AS VECTOR(512));

-- The vector step is materialised on its own so it can be
-- timed in-engine: this is the ANN search, not the joins.
SET @VectorStart = SYSUTCDATETIME();

INSERT @VectorCandidates (document_id, chunk_number, Distance, Position)
SELECT ranked.document_id, ranked.chunk_number, ranked.Distance,
       ROW_NUMBER() OVER (ORDER BY ranked.Distance)
FROM (
  SELECT TOP (@candidates) WITH APPROXIMATE
    chunk.document_id, chunk.chunk_number,
    vector_result.distance AS Distance
  FROM VECTOR_SEARCH(
    TABLE  = dbo.pmc_chunks AS chunk,
    COLUMN = embedding,
    SIMILAR_TO = @QueryVector,
    METRIC = 'COSINE'
  ) AS vector_result
  -- Filters run inside the vector search, not after it.
  WHERE chunk.is_boilerplate = 0__VECTOR_FILTER__
  ORDER BY vector_result.distance
) AS ranked;

SET @VectorMicroseconds =
  DATEDIFF_BIG(microsecond, @VectorStart, SYSUTCDATETIME());

-- Keyword candidates come from the full-text index.
INSERT @KeywordCandidates (document_id, chunk_number, Position)
SELECT TOP (@candidates)
  chunk.document_id, chunk.chunk_number,
  ROW_NUMBER() OVER (ORDER BY ranked.[RANK] DESC)
FROM FREETEXTTABLE(dbo.pmc_chunks, text_chunk,
                   @queryText, @candidates) AS ranked
INNER JOIN dbo.pmc_chunks AS chunk
  ON chunk.chunk_id = ranked.[KEY]
WHERE chunk.is_boilerplate = 0__KEYWORD_FILTER__
ORDER BY ranked.[RANK] DESC;

-- Fuse vector and full-text positions with reciprocal rank fusion.
WITH Fused AS (
  SELECT candidate.document_id, candidate.chunk_number,
    SUM(1.0 / (60.0 + candidate.Position)) AS Score,
    MIN(candidate.Distance) AS Distance
  FROM (
    SELECT document_id, chunk_number, Position, Distance
    FROM @VectorCandidates
    UNION ALL
    SELECT document_id, chunk_number, Position, NULL
    FROM @KeywordCandidates
  ) AS candidate
  GROUP BY candidate.document_id, candidate.chunk_number
),
BestPerDocument AS (
  SELECT document_id, chunk_number, Score, Distance,
    ROW_NUMBER() OVER (
      PARTITION BY document_id
      ORDER BY Score DESC, chunk_number
    ) AS DocumentRank
  FROM Fused
)
SELECT TOP (@top)
  CONCAT('PMC', document.pmcid) AS PmcId,
  document.title, chunk.text_chunk AS Passage,
  previous_chunk.text_chunk AS PreviousPassage,
  next_chunk.text_chunk AS NextPassage
FROM BestPerDocument AS best
INNER JOIN dbo.pmc_chunks AS chunk
  ON chunk.document_id = best.document_id
 AND chunk.chunk_number = best.chunk_number
INNER JOIN dbo.pmc_documents AS document
  ON document.document_id = best.document_id
LEFT JOIN dbo.pmc_chunks AS previous_chunk
  ON previous_chunk.document_id = best.document_id
 AND previous_chunk.chunk_number = best.chunk_number - 1
LEFT JOIN dbo.pmc_chunks AS next_chunk
  ON next_chunk.document_id = best.document_id
 AND next_chunk.chunk_number = best.chunk_number + 1
WHERE best.DocumentRank = 1
ORDER BY best.Score DESC;`

const VECTOR_SEARCH_SQL = `DECLARE @QueryVector VECTOR(512) =
  CAST(@queryVectorJson AS VECTOR(512));

SET @VectorStart = SYSUTCDATETIME();

SELECT TOP (@candidates) WITH APPROXIMATE
  chunk.document_id,
  chunk.chunk_number,
  vector_result.distance AS Distance
FROM VECTOR_SEARCH(
  TABLE  = __CHUNKS_TABLE__ AS chunk,
  COLUMN = embedding,
  SIMILAR_TO = @QueryVector,
  METRIC = 'COSINE'
) AS vector_result
ORDER BY vector_result.distance;

-- The API keeps the best passage per article, joins article
-- metadata, and returns the neighboring chunks for context.`

const environmentButtons: Record<Environment, string> = {
  small: '3K',
  million: '1M',
  replica: 'Named Replica',
}

const environmentTables: Record<Environment, string> = {
  small: 'dbo.pmc_chunks',
  million: 'dbo.pmc_chunks_1M',
  replica: 'dbo.pmc_chunks_1M',
}

const visibleEnvironments: Environment[] = ['small', 'million', 'replica']

const modeLabels: Record<SearchMode, string> = {
  vector: 'Vector',
  keyword: 'Keyword',
  hybrid: 'Hybrid',
}

function formatCount(value: number | null | undefined) {
  return value === null || value === undefined ? '--' : new Intl.NumberFormat('en-US').format(value)
}

function App() {
  const [workspace, setWorkspace] = useState<Workspace>('evidence')
  const [environment, setEnvironment] = useState<Environment>('million')
  const [primaryLabel, setPrimaryLabel] = useState('1M')
  const mode: SearchMode = environment === 'small' ? 'hybrid' : 'vector'
  const [peerReviewedOnly, setPeerReviewedOnly] = useState(false)
  const [query, setQuery] = useState(DEMO_QUERIES[0])
  const [executedQuery, setExecutedQuery] = useState('')
  const [view, setView] = useState<ResultView>('evidence')
  const [evidence, setEvidence] = useState<Evidence[]>([])
  const [selectedResult, setSelectedResult] = useState(0)
  const [isSearching, setIsSearching] = useState(false)
  const [metrics, setMetrics] = useState<SearchResponse | null>(null)
  const [readiness, setReadiness] = useState<ReadinessResponse | null>(null)
  const [notice, setNotice] = useState('Ask a question to run a search.')

  useEffect(() => {
    const controller = new AbortController()
    fetch(`${API_BASE_URL}/api/readiness/${environment}`, { signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error('Readiness unavailable')
        return response.json() as Promise<ReadinessResponse>
      })
      .then((value) => {
        setReadiness(value)
        if (value.environment === 'million') {
          setPrimaryLabel(value.databaseLabel.replace(/ primary$/, ''))
        }
        setNotice(value.ready ? value.message : `${value.databaseLabel}: ${value.message}`)
      })
      .catch(() => {
        setReadiness(null)
        setNotice('The search API is not reachable.')
      })
    return () => controller.abort()
  }, [environment])

  const chooseEnvironment = (next: Environment) => {
    setEnvironment(next)
    setMetrics(null)
    setReadiness(null)
    setEvidence([])
    setExecutedQuery('')
    setNotice('Database changed. Run the question again.')
  }

  const runSearch = async (event: FormEvent) => {
    event.preventDefault()
    const trimmed = query.trim()
    if (!trimmed) return

    setIsSearching(true)
    setNotice('Running search in Azure SQL...')

    try {
      const response = await fetch(`${API_BASE_URL}/api/search`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          environment,
          query: trimmed,
          mode,
          peerReviewedOnly: environment === 'small' && peerReviewedOnly,
        }),
      })
      if (!response.ok) {
        const error = (await response.json().catch(() => ({}))) as { message?: string }
        throw new Error(error.message ?? `Search returned ${response.status}`)
      }
      const payload = (await response.json()) as SearchResponse
      setMetrics(payload)
      setEvidence(payload.evidence)
      setSelectedResult(0)
      setExecutedQuery(trimmed)
      setNotice(
        payload.evidence.length > 0
          ? `Search returned ${payload.evidence.length} articles using the vector index.`
          : 'No articles matched that question.',
      )
    } catch (error) {
      setMetrics(null)
      setEvidence([])
      setNotice(error instanceof Error ? error.message : 'Search failed.')
    } finally {
      setIsSearching(false)
    }
  }

  const selectedEvidence = evidence[selectedResult]
  const isLive = metrics !== null

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="#main">
          Caldova
        </a>
        <nav className="primary-nav" aria-label="Primary navigation">
          <button className={workspace === 'evidence' ? 'active' : ''} type="button" onClick={() => setWorkspace('evidence')}>Evidence</button>
          <button className={workspace === 'agent' ? 'active' : ''} type="button" onClick={() => setWorkspace('agent')}><Bot size={15} /> Agent</button>
          <a href="#trials">Trials</a>
          <a href="#safety">Safety</a>
        </nav>
        <div className="profile">
          <span>Research workspace</span>
          <span className="avatar">AH</span>
          <ChevronDown size={15} aria-hidden="true" />
        </div>
      </header>

      {workspace === 'agent' ? <AgentWorkspace /> : <main id="main">
        <section className="search-workspace" aria-labelledby="page-title">
          <div className="workspace-heading">
            <div>
              <p className="eyebrow">Biomedical evidence explorer</p>
              <h1 id="page-title">Find the evidence. See the source.</h1>
            </div>
            <div className="environment-control" aria-label="Search configuration">
              <span className="control-label">Database</span>
              <div className="segment-group environment-segments">
                {visibleEnvironments.map((option) => (
                  <button
                    className={environment === option ? 'selected' : ''}
                    key={option}
                    type="button"
                    onClick={() => chooseEnvironment(option)}
                    aria-pressed={environment === option}
                  >
                    {option === 'million' ? primaryLabel : environmentButtons[option]}
                  </button>
                ))}
              </div>
              <p className="scale-note">
                1M is the indexed default. The setup guide covers 10K and 100K for a
                lower-cost rehearsal.
              </p>
              <span className="control-label">Evidence</span>
              <div className="segment-group">
                <button
                  className={peerReviewedOnly ? '' : 'selected'}
                  type="button"
                  onClick={() => setPeerReviewedOnly(false)}
                  aria-pressed={!peerReviewedOnly}
                >
                  All sources
                </button>
                <button
                  className={peerReviewedOnly ? 'selected' : ''}
                  type="button"
                  onClick={() => setPeerReviewedOnly(true)}
                  aria-pressed={peerReviewedOnly}
                  disabled={environment !== 'small'}
                >
                  Peer-reviewed
                </button>
              </div>
            </div>
          </div>

          <form className="search-form" onSubmit={runSearch}>
            <Search className="search-icon" size={21} aria-hidden="true" />
            <input
              aria-label="Evidence question"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Ask a biomedical evidence question"
            />
            <button className="search-button" type="submit" disabled={isSearching}>
              {isSearching ? <span className="spinner" /> : <Sparkles size={17} />}
              {isSearching ? 'Searching' : 'Search evidence'}
            </button>
          </form>
        </section>

        <section className="status-band" aria-live="polite">
          <div className={`connection-status ${isLive ? 'live' : ''}`}>
            <span className="status-dot" />
            <div>
              <strong>{isLive ? 'Live measurement' : readiness?.ready ? 'Live ready' : 'Not ready'}</strong>
              <span>{notice}</span>
            </div>
          </div>
          <div className="metric-strip">
            <div className="metric">
              <FileText size={18} />
              <span>Articles returned<strong>{evidence.length > 0 ? evidence.length : '--'}</strong></span>
            </div>
            <div className="metric">
              <BookOpen size={18} />
              <span>Rows searched<strong>{formatCount(isSearching ? null : metrics?.chunkCount)}</strong></span>
            </div>
            <div className="metric featured">
              <Clock3 size={18} />
              <span>Vector search<strong>
                {metrics?.vectorSearchMs != null ? `${metrics.vectorSearchMs.toFixed(1)} ms` : '--'}
              </strong></span>
            </div>
          </div>
        </section>

        <section className="results-workspace" aria-labelledby="results-heading">
          <div className="results-header">
            <div>
              <p className="eyebrow">Search response</p>
              <h2 id="results-heading">Evidence for your question</h2>
              {executedQuery && <p className="executed-query">“{executedQuery}”</p>}
            </div>
            <div className="view-tabs" role="tablist" aria-label="Result view">
              <button
                className={view === 'evidence' ? 'active' : ''}
                type="button" role="tab" aria-selected={view === 'evidence'}
                onClick={() => setView('evidence')}
              >
                Evidence
              </button>
              <button
                className={view === 'sql' ? 'active' : ''}
                type="button" role="tab" aria-selected={view === 'sql'}
                onClick={() => setView('sql')}
              >
                SQL query
              </button>
            </div>
          </div>

          {view === 'sql' ? (
            <div className="sql-view">
              <div className="sql-caption">
                <div><Check size={17} /> Query for the selected database target</div>
              </div>
              <pre><code>{environment === 'small'
                ? SEARCH_SQL
                    .replace('__VECTOR_FILTER__', peerReviewedOnly ? '\n    AND chunk.is_preprint = 0' : '')
                    .replace('__KEYWORD_FILTER__', peerReviewedOnly ? '\n  AND chunk.is_preprint = 0' : '')
                : VECTOR_SEARCH_SQL.replace(
                    '__CHUNKS_TABLE__',
                    metrics?.tableName ?? readiness?.tableName ?? environmentTables[environment],
                  )}</code></pre>
            </div>
          ) : evidence.length > 0 && selectedEvidence ? (
            <div className="evidence-layout">
              <div className="evidence-list" aria-label="Ranked evidence">
                {evidence.map((item, index) => (
                  <button
                    type="button"
                    className={`evidence-card ${selectedResult === index ? 'selected' : ''}`}
                    key={`${item.documentId}-${item.chunkNumber}`}
                    onClick={() => setSelectedResult(index)}
                  >
                    <span className="rank">{String(index + 1).padStart(2, '0')}</span>
                    <span className="evidence-content">
                      <span className="source-line">
                        <span><FileText size={14} /> {item.documentId}</span>
                        {item.distance !== null && (
                          <span>{((1 - item.distance) * 100).toFixed(1)}% match</span>
                        )}
                      </span>
                      <strong>{item.title}</strong>
                      <span className="passage">{item.passage}</span>
                    </span>
                    <ArrowUpRight className="open-icon" size={17} aria-hidden="true" />
                  </button>
                ))}
              </div>

              <aside className="evidence-detail" aria-label="Selected evidence detail">
                <div className="detail-kicker"><span /> Evidence passage</div>
                <h3>{selectedEvidence.title}</h3>
                {selectedEvidence.previousPassage && (
                  <p className="context-passage">…{selectedEvidence.previousPassage.slice(-260)}</p>
                )}
                <blockquote>{selectedEvidence.passage}</blockquote>
                {selectedEvidence.nextPassage && (
                  <p className="context-passage">{selectedEvidence.nextPassage.slice(0, 260)}…</p>
                )}
                <dl>
                  <div><dt>Source</dt><dd>{selectedEvidence.documentId}</dd></div>
                  <div><dt>Passage</dt><dd>Chunk {selectedEvidence.chunkNumber}</dd></div>
                  <div>
                    <dt>Cosine distance</dt>
                    <dd>{selectedEvidence.distance !== null ? selectedEvidence.distance.toFixed(4) : '--'}</dd>
                  </div>
                  <div><dt>Search</dt><dd>{modeLabels[metrics?.mode ?? mode]}</dd></div>
                </dl>
                <a
                  href={`https://pmc.ncbi.nlm.nih.gov/articles/${selectedEvidence.documentId}/`}
                  target="_blank"
                  rel="noreferrer"
                >
                  Open source article <ArrowUpRight size={15} />
                </a>
              </aside>
            </div>
          ) : (
            <div className="empty-state">
              <Search size={28} />
              <h3>No evidence yet</h3>
              <p>{readiness?.ready ? 'Ask a question to search the corpus.' : notice}</p>
            </div>
          )}
        </section>
      </main>}
      <footer>
        <span>Caldova research systems</span>
        <span>Azure SQL · Vector search</span>
      </footer>
    </div>
  )
}

export default App

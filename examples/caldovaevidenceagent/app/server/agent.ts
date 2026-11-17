import { DefaultAzureCredential } from '@azure/identity'
import { Router } from 'express'
import { performance } from 'node:perf_hooks'

type AgentRequest = { message?: unknown; sessionId?: unknown; responseId?: unknown; conversationId?: unknown }
type FoundryOutput = { type?: string; name?: string; content?: Array<{ type?: string; text?: string }> }
type FoundryResponse = {
  id?: string
  status?: string
  error?: { code?: string; message?: string }
  output?: FoundryOutput[]
  conversation?: { id?: string }
  agent_session_id?: string
}
type FoundryEvent = { type?: string; response?: FoundryResponse }

class AgentApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) { super(message) }
}

const agentName = process.env.CALDOVA_AGENT_NAME?.trim() || 'caldova-evidence-hosted'
const agentVersion = process.env.CALDOVA_AGENT_VERSION?.trim() || '6'
const agentEndpoint = process.env.CALDOVA_AGENT_ENDPOINT?.trim()
const credential = new DefaultAzureCredential()
const agentRouter = Router()
const sqlMcpToolNames = new Set(['get_article_context', 'get_corpus_status', 'search_evidence'])

function getString(value: unknown, field: string, maxLength: number) {
  if (value === undefined || value === null || value === '') return undefined
  if (typeof value !== 'string' || value.length > maxLength) {
    throw new AgentApiError(400, 'INVALID_REQUEST', `${field} is invalid.`)
  }
  return value
}

function extractResponseText(payload: FoundryResponse) {
  return (payload.output ?? [])
    .filter((item) => item.type === 'message')
    .flatMap((item) => item.content ?? [])
    .filter((item) => item.type === 'output_text' && typeof item.text === 'string')
    .map((item) => item.text)
    .join('\n')
    .trim()
}

function parseEventStream(content: string) {
  let terminalResponse: FoundryResponse | undefined
  for (const line of content.split(/\r?\n/)) {
    if (!line.startsWith('data: ')) continue
    try {
      const event = JSON.parse(line.slice(6)) as FoundryEvent
      if (event.type === 'response.completed' || event.type === 'response.failed') {
        terminalResponse = event.response
      }
    } catch {
      // Ignore keep-alives and incomplete non-data lines.
    }
  }
  if (!terminalResponse) {
    throw new AgentApiError(502, 'INVALID_STREAM', 'The hosted agent stream ended without a terminal response.')
  }
  return terminalResponse
}

async function invokeAgent(message: string, sessionId?: string, responseId?: string, conversationId?: string) {
  if (!agentEndpoint) throw new AgentApiError(503, 'AGENT_NOT_CONFIGURED', 'CALDOVA_AGENT_ENDPOINT is not configured.')
  const accessToken = await credential.getToken('https://ai.azure.com/.default')
  if (!accessToken) throw new AgentApiError(503, 'TOKEN_UNAVAILABLE', 'Could not acquire a Foundry access token.')

  let activeSessionId = sessionId
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    const body = {
      agent_reference: { type: 'agent_reference', name: agentName, version: agentVersion },
      input: message,
      stream: true,
      ...(activeSessionId ? { agent_session_id: activeSessionId } : {}),
      ...(responseId ? { previous_response_id: responseId } : conversationId ? { conversation: conversationId } : {}),
    }
    const foundryResponse = await fetch(agentEndpoint, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(600_000),
    })
    const responseContent = await foundryResponse.text()
    const errorPayload = foundryResponse.ok
      ? undefined
      : JSON.parse(responseContent || '{}') as FoundryResponse
    activeSessionId = errorPayload?.agent_session_id || foundryResponse.headers.get('x-agent-session-id') || activeSessionId

    if (foundryResponse.status === 424 && errorPayload?.error?.code === 'session_not_ready' && attempt === 1) {
      activeSessionId ||= errorPayload.error.message?.match(/Session '([^']+)'/)?.[1]
      if (!activeSessionId) throw new AgentApiError(503, 'SESSION_NOT_READY', 'The hosted agent session is not ready.')
      continue
    }
    if (!foundryResponse.ok) {
      throw new AgentApiError(
        foundryResponse.status,
        errorPayload?.error?.code ?? 'AGENT_FAILED',
        errorPayload?.error?.message ?? `Foundry returned ${foundryResponse.status}.`,
      )
    }

    const payload = parseEventStream(responseContent)
    activeSessionId = payload.agent_session_id || activeSessionId
    if (payload.status === 'failed') {
      throw new AgentApiError(502, payload.error?.code ?? 'AGENT_FAILED', payload.error?.message ?? 'The hosted agent failed.')
    }

    const text = extractResponseText(payload)
    if (!text) throw new AgentApiError(502, 'EMPTY_RESPONSE', 'The agent returned no briefing text.')
    return {
      text,
      sessionId: activeSessionId,
      responseId: payload.id,
      conversationId: payload.conversation?.id || conversationId,
      toolCalls: (payload.output ?? []).filter((item) =>
        (item.type === 'mcp_call' || item.type === 'function_call') &&
        typeof item.name === 'string' &&
        sqlMcpToolNames.has(item.name),
      ).length,
    }
  }
  throw new AgentApiError(503, 'SESSION_NOT_READY', 'The hosted agent session is still starting. Retry the request.')
}

agentRouter.get('/readiness', (_request, response) => {
  response.json({ configured: Boolean(agentEndpoint), agent: agentName, version: agentVersion })
})

agentRouter.post('/', async (request, response) => {
  const started = performance.now()
  try {
    const body = request.body as AgentRequest
    const message = getString(body.message, 'message', 2_000)?.trim()
    if (!message) throw new AgentApiError(400, 'INVALID_MESSAGE', 'Provide an evidence request.')
    const result = await invokeAgent(
      message,
      getString(body.sessionId, 'sessionId', 200),
      getString(body.responseId, 'responseId', 200),
      getString(body.conversationId, 'conversationId', 200),
    )
    response.json({
      ...result,
      sources: [...new Set(result.text.match(/PMC\d+/g) ?? [])],
      version: agentVersion,
      durationMs: performance.now() - started,
    })
  } catch (error) {
    const apiError = error as AgentApiError
    response.status(apiError?.status ?? 500).json({
      code: apiError?.code ?? 'AGENT_REQUEST_FAILED',
      message: apiError?.message ?? 'The evidence investigation failed.',
    })
  }
})

export { agentRouter }
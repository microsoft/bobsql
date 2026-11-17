import { useEffect, useRef, useState } from 'react'
import type { FormEvent, ReactNode } from 'react'
import { ArrowUpRight, BookOpen, Check, CircleAlert, FileText, FlaskConical, RotateCcw, Send, Sparkles } from 'lucide-react'
import './AgentWorkspace.css'

const API_BASE_URL = (import.meta.env.VITE_API_BASE_URL ?? '').replace(/\/$/, '')
const BRIEFING_PROMPT = 'How might intestinal microbiome disruption influence anxiety and depression?'
const AGENT_WORKFLOW_STEPS = [
  'Planned 3 research questions',
  'Searched 3 evidence angles',
  'Compared 3 distinct sources',
  'Synthesized briefing',
  'Ready for follow-up',
]

type AgentResponse = {
  text: string; sources: string[]; toolCalls: number; sessionId: string
  responseId: string; conversationId: string; version: string; durationMs: number
}
type Turn = { id: string; role: 'user' | 'assistant'; text: string; sources: string[]; toolCalls?: number; durationMs?: number }
type VisualBriefing = { bottomLine: string; signals: Array<{ label: string; body: string }>; confidence: string; followUp: string }

function renderInline(text: string, keyPrefix: string): ReactNode[] {
  const nodes: ReactNode[] = []
  const tokenPattern = /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)|(PMC\d+)/g
  let cursor = 0
  for (const match of text.matchAll(tokenPattern)) {
    const offset = match.index ?? 0
    if (offset > cursor) nodes.push(text.slice(cursor, offset))
    const label = match[1] ?? match[3]
    const href = match[2] ?? `https://pmc.ncbi.nlm.nih.gov/articles/${match[3]}/`
    nodes.push(<a href={href} key={`${keyPrefix}-${offset}`} target="_blank" rel="noreferrer">{label}<ArrowUpRight size={12} /></a>)
    cursor = offset + match[0].length
  }
  if (cursor < text.length) nodes.push(text.slice(cursor))
  return nodes
}

function renderText(text: string): ReactNode[] {
  return text.split('\n').map((line, index) => {
    const trimmed = line.trim()
    if (!trimmed) return <span className="agent-response-space" key={`space-${index}`} />
    const heading = trimmed.match(/^#{1,3}\s+(.+)$/)
    if (heading) return <h3 key={`heading-${index}`}>{heading[1]}</h3>
    return <p key={`line-${index}`}>{renderInline(trimmed, `line-${index}`)}</p>
  })
}

function parseVisualBriefing(text: string): VisualBriefing | null {
  const sections = new Map<string, string[]>()
  let currentSection = ''
  for (const line of text.split('\n')) {
    const trimmed = line.trim()
    const heading = trimmed.match(/^#{1,3}\s+(.+)$/)
    if (heading) {
      currentSection = heading[1].trim().toLowerCase()
      sections.set(currentSection, [])
    } else if (trimmed && currentSection) {
      sections.get(currentSection)?.push(trimmed)
    }
  }

  const bottomLine = sections.get('bottom line')?.join(' ') ?? ''
  const signalLines = sections.get('evidence signals') ?? sections.get('evidence comparison') ?? []
  const signals = signalLines.filter((line) => /^[-*]\s+/.test(line)).slice(0, 3).map((line, index) => {
    const content = line.replace(/^[-*]\s+/, '')
    const labeled = content.match(/^\*\*([^*]+)\*\*\s*[—:–-]\s*(.+)$/)
    return { label: labeled?.[1] ?? `Signal ${index + 1}`, body: labeled?.[2] ?? content }
  })
  const confidence = (sections.get('confidence') ?? sections.get('limitations and confidence') ?? [])
    .join(' ').replace(/^[-*]\s+/, '')
  const followUp = (sections.get('suggested follow-up') ?? sections.get('next research question') ?? [])
    .join(' ').replace(/^[-*]\s+/, '')

  return bottomLine && signals.length === 3 && confidence && followUp
    ? { bottomLine, signals, confidence, followUp }
    : null
}

function renderAgentResponse(text: string): ReactNode {
  const briefing = parseVisualBriefing(text)
  if (!briefing) return renderText(text)
  return <div className="agent-briefing">
    <section className="agent-briefing-bottomline">
      <Sparkles size={19} />
      <div><span>Bottom line</span><p>{renderInline(briefing.bottomLine, 'bottom-line')}</p></div>
    </section>
    <section className="agent-briefing-signals" aria-label="Evidence signals">
      {briefing.signals.map((signal, index) => <div className="agent-briefing-signal" key={`${signal.label}-${index}`}>
        <b>{String(index + 1).padStart(2, '0')}</b>
        <span><strong>{signal.label}</strong><p>{renderInline(signal.body, `signal-${index}`)}</p></span>
      </div>)}
    </section>
    <section className="agent-briefing-summary">
      <div><CircleAlert size={17} /><span><strong>Confidence</strong><p>{renderInline(briefing.confidence, 'confidence')}</p></span></div>
      <div className="agent-briefing-next"><Send size={17} /><span><strong>Suggested follow-up</strong><p>{renderInline(briefing.followUp, 'follow-up')}</p></span></div>
    </section>
  </div>
}

function AgentWorkspace() {
  const [configured, setConfigured] = useState(false)
  const [version, setVersion] = useState('--')
  const [turns, setTurns] = useState<Turn[]>([])
  const [question, setQuestion] = useState(BRIEFING_PROMPT)
  const [sessionId, setSessionId] = useState('')
  const [responseId, setResponseId] = useState('')
  const [conversationId, setConversationId] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState('')
  const [workflowStage, setWorkflowStage] = useState(-1)
  const endRef = useRef<HTMLDivElement>(null)
  const workflowTimers = useRef<number[]>([])

  const clearWorkflowTimers = () => {
    workflowTimers.current.forEach((timer) => window.clearTimeout(timer))
    workflowTimers.current = []
  }

  useEffect(() => {
    fetch(`${API_BASE_URL}/api/agent/readiness`)
      .then((response) => response.json() as Promise<{ configured: boolean; version: string }>)
      .then((value) => { setConfigured(value.configured); setVersion(value.version) })
      .catch(() => setConfigured(false))
  }, [])
  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }) }, [turns, pending])
  useEffect(() => () => clearWorkflowTimers(), [])

  const sources = [...new Set(turns.flatMap((turn) => turn.sources))]
  const latest = [...turns].reverse().find((turn) => turn.role === 'assistant')
  const assistantTurnCount = turns.filter((turn) => turn.role === 'assistant').length
  const guidedFollowUp = [
    { label: 'Find strongest causal evidence', prompt: 'Which of those three studies gives the strongest causal evidence, and why?' },
    { label: 'Challenge that conclusion', prompt: 'What limitation most weakens that causal conclusion?' },
    { label: 'Design the next experiment', prompt: 'What experiment should researchers run next to resolve that limitation?' },
  ][assistantTurnCount - 1]

  const investigate = async (event: FormEvent) => {
    event.preventDefault()
    const message = question.trim()
    if (!message || pending) return
    clearWorkflowTimers()
    setWorkflowStage(0)
    workflowTimers.current = [
      window.setTimeout(() => setWorkflowStage(1), 1800),
      window.setTimeout(() => setWorkflowStage(2), 5000),
      window.setTimeout(() => setWorkflowStage(3), 9000),
    ]
    setTurns((current) => [...current, { id: crypto.randomUUID(), role: 'user', text: message, sources: [] }])
    setQuestion(''); setError(''); setPending(true)
    try {
      const response = await fetch(`${API_BASE_URL}/api/agent`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message, sessionId: sessionId || undefined, responseId: responseId || undefined, conversationId: conversationId || undefined }),
      })
      const payload = (await response.json().catch(() => ({}))) as AgentResponse & { message?: string }
      if (!response.ok) throw new Error(payload.message ?? `Agent returned ${response.status}.`)
      setSessionId(payload.sessionId); setResponseId(payload.responseId); setConversationId(payload.conversationId)
      setTurns((current) => [...current, { id: crypto.randomUUID(), role: 'assistant', text: payload.text, sources: payload.sources, toolCalls: payload.toolCalls, durationMs: payload.durationMs }])
      setWorkflowStage(4)
    } catch (requestError) {
      setWorkflowStage(-1)
      setError(requestError instanceof Error ? requestError.message : 'The investigation failed.')
    } finally { clearWorkflowTimers(); setPending(false) }
  }

  const reset = () => { clearWorkflowTimers(); setTurns([]); setSessionId(''); setResponseId(''); setConversationId(''); setQuestion(BRIEFING_PROMPT); setError(''); setWorkflowStage(-1) }

  return (
    <main className={`agent-main ${turns.length === 0 ? 'initial' : ''}`} id="main">
      <section className="agent-titlebar">
        <div><p className="eyebrow">Biomedical evidence explorer</p><h1>Investigate with an evidence agent.</h1></div>
        <div className={`agent-ready ${configured ? 'online' : ''}`}><span />{configured ? `Hosted agent v${version}` : 'Agent unavailable'}</div>
      </section>
      <section className={`agent-surface ${turns.length === 0 ? 'initial' : ''}`}>
        <div className={`agent-conversation-column ${turns.length === 0 ? 'initial' : ''}`}>
          <div className="agent-panel-heading">
            <div><p className="eyebrow">Agent workspace</p><h2>Research conversation</h2></div>
            {turns.length > 0 && <button type="button" onClick={reset} title="New investigation"><RotateCcw size={17} /></button>}
          </div>
          {workflowStage >= 0 && <section className="agent-workflow" aria-label="Agent research workflow">
            {AGENT_WORKFLOW_STEPS.map((label, index) => {
              const state = !pending && workflowStage === 4
                ? 'complete'
                : index < workflowStage ? 'complete' : index === workflowStage ? 'active' : 'waiting'
              return <div className={`agent-workflow-step ${state}`} key={label} aria-current={state === 'active' ? 'step' : undefined}>
                <span className="agent-workflow-marker">{state === 'complete' ? <Check size={14} /> : index + 1}</span>
                <span>{label}</span>
              </div>
            })}
          </section>}
          <div className="agent-conversation" aria-live="polite">
            {turns.length === 0 && <div className="agent-empty"><FlaskConical size={27} /><h3>Start an evidence investigation</h3><p>The agent plans searches, reads surrounding passages, and returns a grounded briefing.</p></div>}
            {turns.map((turn) => <article className={`agent-turn ${turn.role}`} key={turn.id}>
              <div className="agent-turn-label">{turn.role === 'user' ? 'Research request' : 'Caldova analysis'}</div>
              <div className="agent-turn-body">{turn.role === 'assistant' ? renderAgentResponse(turn.text) : <p>{turn.text}</p>}</div>
              {turn.role === 'assistant' && <div className="agent-turn-meta"><span><Check size={13} /> {turn.sources.length} sources</span><span>{turn.toolCalls} evidence calls</span><span>{turn.durationMs ? `${(turn.durationMs / 1000).toFixed(1)}s` : '--'}</span></div>}
            </article>)}
            {pending && <div className="agent-investigating"><span className="agent-spinner" /><div><strong>Investigating the corpus</strong><span>Running three focused searches in parallel, then synthesizing</span></div></div>}
            {error && <div className="agent-error"><CircleAlert size={17} />{error}</div>}
            <div ref={endRef} />
          </div>
          {(responseId || conversationId) && !pending && guidedFollowUp && <button className="agent-followup" type="button" onClick={() => setQuestion(guidedFollowUp.prompt)}>{guidedFollowUp.label}</button>}
          <form className="agent-composer" onSubmit={investigate}>
            <textarea aria-label="Evidence request" value={question} onChange={(event) => setQuestion(event.target.value)} rows={3} />
            <button type="submit" disabled={!question.trim() || pending} title="Send request"><Send size={18} /></button>
          </form>
        </div>
        <aside className="agent-source-rail">
          <div className="agent-source-heading"><div><p className="eyebrow">Grounding</p><h2>Evidence sources</h2></div><span>{sources.length || '--'}</span></div>
          <div className="agent-source-list">{sources.length === 0
            ? <div className="agent-source-empty"><FileText size={23} /><span>Sources appear with the briefing.</span></div>
            : sources.map((source, index) => <a href={`https://pmc.ncbi.nlm.nih.gov/articles/${source}/`} key={source} target="_blank" rel="noreferrer"><b>{String(index + 1).padStart(2, '0')}</b><span><strong>{source}</strong><small>PubMed Central</small></span><ArrowUpRight size={15} /></a>)}</div>
          <div className="agent-activity"><p className="eyebrow">Agent path</p><dl><div><dt>Model</dt><dd>GPT-5</dd></div><div><dt>Skill</dt><dd>Evidence review</dd></div><div><dt>Tools</dt><dd>{latest?.toolCalls ?? '--'}</dd></div><div><dt>Data</dt><dd>Azure SQL</dd></div></dl></div>
        </aside>
      </section>
      <div className="agent-techline"><Sparkles size={14} /> Microsoft Foundry <BookOpen size={14} /> DAB SQL MCP</div>
    </main>
  )
}

export default AgentWorkspace
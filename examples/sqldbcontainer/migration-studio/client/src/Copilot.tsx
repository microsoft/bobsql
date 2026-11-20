import { useEffect, useRef, useState } from 'react';
import { Button, Spinner, Tab, TabList, Textarea } from '@fluentui/react-components';
import { ArrowUp24Regular, Sparkle24Regular } from '@fluentui/react-icons';
import { Notice, StateBadge } from './components.tsx';
import { SkillTrace } from './SkillTrace.tsx';
import { CopilotConnection } from './CopilotConnection.tsx';
import { useRead } from './hooks.ts';
import type { LiveState } from './live.ts';
import type { Status } from './types.ts';

const guidance = [
  { title: 'Source', skill: 'azuresql-db-local-to-cloud' },
  { title: 'Azure destination', skill: 'provision-azure-sql-db' },
  { title: 'Review', skill: 'sql-bacpac-to-azure-sql-db-migration' },
  { title: 'Migrate', skill: 'sql-bacpac-to-azure-sql-db-migration' },
  { title: 'Verify', skill: 'azuresql-db-local-to-cloud' },
];

export function Copilot({ status: studioStatus, live, stage }: { status?: Status; live: LiveState; stage: number }) {
  const connection = useRead<Status['copilot']>('/api/copilot/status');
  const copilot = connection.data ?? studioStatus?.copilot;
  const status = studioStatus && { ...studioStatus, copilot: copilot ?? studioStatus.copilot };
  const [text, setText] = useState('');
  const [model, setModel] = useState('');
  const [view, setView] = useState<'flow' | 'chat'>('flow');
  const [guiding, setGuiding] = useState(false);
  const guidedSteps = useRef(new Set<number>());
  const step = guidance[stage];
  const bottom = useRef<HTMLDivElement>(null);
  const stickToBottom = useRef(true);
  useEffect(() => {
    if (stickToBottom.current) bottom.current?.scrollIntoView({ block: 'nearest', behavior: 'instant' });
  }, [live.messages, view]);
  const authenticated = copilot?.authenticated === true;
  const modelAvailable = !model || copilot?.models.some(item => item.id === model);
  const enabled = authenticated && live.connection === 'connected' && !live.sending && modelAvailable;
  useEffect(() => {
    if (!guiding || !enabled || guidedSteps.current.has(stage)) return;
    guidedSteps.current.add(stage);
    void live.send(
      `The operator is on the "${step.title}" step in SQL Migration Studio. ` +
      `Use read_skill_instructions to read "${step.skill}", then call inspect_readiness and get_migration_status. ` +
      'Explain in at most three short bullets how that skill guides this step, what the evidence says, and the next safe operator action. ' +
      'Do not execute or approve migration operations. Do not assume a wizard selection or any source or Azure identifiers. ' +
      'Only public step names are supplied in this request.',
      model || undefined);
  }, [guiding, enabled, stage, step, model, live.send]);
  const latestAnswer = live.messages.filter(message => message.role === 'assistant' && message.text).at(-1);
  async function send() {
    const sent = await live.send(text, model || undefined);
    if (sent) setText('');
  }
  return <aside className="copilot-panel" aria-label="Copilot assistant">
    <header className="copilot-header"><div className="copilot-symbol"><Sparkle24Regular /></div><div><h2>Migration Copilot</h2><p>Follow the agent · skills · tools</p></div></header>
    <CopilotConnection status={copilot} error={connection.error} onCheck={connection.reload} />
    <TabList className="agent-tabs" aria-label="Copilot views" selectedValue={view} onTabSelect={(_, data) => setView(data.value === 'chat' ? 'chat' : 'flow')}>
      <Tab id="agent-flow-tab" value="flow" aria-controls="agent-flow-panel">Agent flow</Tab>
      <Tab id="agent-chat-tab" value="chat" aria-controls="agent-chat-panel">Chat{live.sending ? ' · responding' : ''}</Tab>
    </TabList>
    {view === 'flow' ? <div id="agent-flow-panel" role="tabpanel" aria-labelledby="agent-flow-tab" className="agent-flow-panel">
      <div className="copilot-guide">
        <strong>Copilot guide · {step.title}</strong>
        <p>{guiding ? 'The agent consults a relevant skill once per step as you move through the migration. Each request uses Copilot usage.' : 'Start the guide to let Copilot consult skills as you move through each step. This makes real agent requests and uses your Copilot allowance.'}</p>
        <div className="inline-actions"><Button appearance="primary" disabled={!guiding && !enabled} onClick={() => setGuiding(value => !value)}>{guiding ? 'Stop guide' : 'Start Copilot guide'}</Button></div>
        {guiding && <p className="muted">Stopping the guide stops future requests; an active response may still finish.</p>}
        {live.sending && <div className="chat-activity" role="status"><Spinner size="tiny" /> Copilot is responding. Watch for actual tool and skill events below.</div>}
        {live.chatError && <Notice title="Copilot request failed" danger>{live.chatError}</Notice>}
        {latestAnswer && <details className="guide-answer" open><summary>Latest Copilot guidance</summary><p>{latestAnswer.text}</p></details>}
      </div>
      <SkillTrace status={status} live={live} />
    </div> : <div id="agent-chat-panel" role="tabpanel" aria-labelledby="agent-chat-tab" className="agent-chat-panel">
    <div className="copilot-status"><StateBadge state={authenticated ? 'connected' : 'not connected'} /><span>{copilot?.status || 'Authentication has not been reported.'}</span></div>
    <div className="copilot-chat" tabIndex={0} aria-label="Conversation" onScroll={event => {
      const element = event.currentTarget;
      stickToBottom.current = element.scrollHeight - element.scrollTop - element.clientHeight < 80;
    }}>
      {!live.messages.length && <div className="chat-welcome"><span className="eyebrow">YOUR MIGRATION, EXPLAINED</span><h3>Clarity at every step.</h3>
        <p>Ask about readiness, the migration plan, or validation evidence.</p>
        <p className="muted">The agent has only read-only tools. The host executes explicitly approved migrations; chat cannot bypass the approval gate.</p>
        <details><summary>Agent tool boundaries</summary><p><code>inspect_readiness</code>, <code>get_migration_status</code>, and <code>read_skill_instructions</code>. No mutating tools or model shell access.</p></details></div>}
      {live.messages.map(message => <article key={message.id} className={`chat-message ${message.role}`}>
        <strong>{message.role === 'user' ? 'You' : 'Copilot'}</strong>
        <div>{message.text || (live.sending ? 'Waiting for the agent…' : 'No response content was received.')}</div>
      </article>)}
      <div ref={bottom} />
    </div>
    {live.sending && <div className="chat-activity" role="status"><Spinner size="tiny" /> Agent request active · awaiting live completion</div>}
    {live.chatError && <Notice title="Copilot request status" danger>{live.chatError}</Notice>}
    <form className="chat-composer" onSubmit={event => { event.preventDefault(); if (enabled && text.trim()) void send(); }}>
      <label className="field"><span>Model</span><select value={model} disabled={!authenticated || live.sending} onChange={event => setModel(event.target.value)}>
        <option value="">Agent default</option>{copilot?.models.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label className="field"><span>Message Copilot</span><Textarea value={text} resize="vertical" disabled={!authenticated || live.sending} placeholder={authenticated ? 'Ask about this migration…' : 'Connect Copilot in the local backend first'} onChange={(_, data) => setText(data.value)} /></label>
      <div className="composer-footer"><span>Sending uses Copilot usage. Readiness checks do not run inference.</span><Button type="submit" appearance="primary" icon={<ArrowUp24Regular />} disabled={!enabled || !text.trim()} aria-label="Send message" /></div>
    </form>
    </div>}
  </aside>;
}

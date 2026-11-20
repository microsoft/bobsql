import { useState } from 'react';
import { Button } from '@fluentui/react-components';
import { DocumentBulletList24Regular, Open24Regular } from '@fluentui/react-icons';
import { StateBadge } from './components.tsx';
import { copilotActivity, safeWebUrl, skillReadState } from './domain.ts';
import type { LiveState } from './live.ts';
import type { Status } from './types.ts';

export function SkillTrace({ status, live }: { status?: Status; live: LiveState }) {
  const [filter, setFilter] = useState('all');
  const trace = copilotActivity(live.events);
  const visible = trace.filter(event => filter === 'all' || event.stage === filter);
  return <section className="skill-trace" aria-label="Copilot skill debugger">
    <header className="trace-header">
      <div><span className="eyebrow">LIVE AGENT INSPECTOR</span><h2><DocumentBulletList24Regular /> Agent flow</h2></div>
      <StateBadge state={status?.copilot.authenticated ? 'connected' : 'not connected'} />
    </header>
    <div className="agent-flow-route" aria-label="Agent architecture, not execution progress"><span>Copilot</span><span aria-hidden="true">→</span><span>Skills</span><span aria-hidden="true">→</span><span>Tools</span></div>
    <p>Only actual Copilot skill reads and tool calls appear here. App discovery and migration operations are not agent activity.</p>
    <div className="trace-toolbar"><label>Show trace <select value={filter} onChange={event => setFilter(event.target.value)}><option value="all">Copilot activity</option><option value="skill">Skill reads</option><option value="tool">Tool calls</option></select></label><span>{visible.length} recorded events</span><Button onClick={live.reconnect}>Reconnect trace</Button></div>
    <div className="trace-console" role="log" aria-label="Recorded Copilot invocations" aria-live="polite" tabIndex={0}>
      {visible.length === 0 ? <div className="trace-empty"><strong>No Copilot activity recorded</strong><p>{status?.copilot.authenticated ? 'Start the Copilot guide above to have the agent consult skills for the current migration step, or send a chat message.' : 'Copilot is not connected. Azure sign-in does not sign in the Copilot SDK.'}</p><p>No simulated calls or app operations are shown.</p></div>
        : <ol>{visible.slice().reverse().map(event => <li key={event.id} data-state={event.state}>
          <div className="trace-event-meta"><time dateTime={event.time}>{new Date(event.time).toLocaleTimeString()}</time><span>{event.stage === 'skill' ? 'SKILL' : event.stage === 'tool' ? 'TOOL' : 'COPILOT'}</span><strong>{event.state}</strong><span>#{event.id}</span></div>
          <strong className="trace-event-title">{event.subject || event.stage}</strong><p>{event.message}</p>
        </li>)}</ol>}
    </div>
    <details className="trace-catalog"><summary>Available skills · {status?.skills.length ?? 'checking'}</summary><p className="muted">These badges change only on recorded Copilot skill reads, not on app activity.</p><div className="trace-skills">
      {status?.skills.map((skill, index) => <details className="trace-skill" key={skill.name}>
        <summary><span className="trace-skill-number">{String(index + 1).padStart(2, '0')}</span><span>{skill.title}<code>{skill.name}</code></span><StateBadge state={skillReadState(trace, skill.name)} /></summary>
        <p>{skill.adaptation}</p><p className="mono">Revision: {skill.revision}</p>
        {safeWebUrl(skill.sourceUrl) && <a href={safeWebUrl(skill.sourceUrl)} target="_blank" rel="noreferrer">Upstream instructions <Open24Regular /></a>}
      </details>)}
      {!status?.skills.length && <p>Waiting for the skill catalog. No skill use has been assumed.</p>}
    </div></details>
    <footer>Newest first · up to 500 shared stream events retained · reads are not execution or proof of model reasoning · no prompts, credentials, or tool payloads shown</footer>
    {live.streamError && <p role="alert">{live.streamError}</p>}
  </section>;
}

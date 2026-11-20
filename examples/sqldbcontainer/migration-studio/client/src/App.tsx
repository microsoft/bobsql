import { useEffect, useRef, useState } from 'react';
import { Button, Checkbox, ProgressBar, Spinner } from '@fluentui/react-components';
import {
  ArrowLeft24Regular, ArrowRight24Regular, Checkmark24Regular, Cloud24Regular,
  Database24Regular, DocumentBulletList24Regular, Open24Regular, Play24Regular,
  PlugConnected24Regular, ShieldCheckmark24Regular, Sparkle24Regular,
} from '@fluentui/react-icons';
import { ApiError, errorMessage, get, post } from './api.ts';
import { Copilot } from './Copilot.tsx';
import { Destination } from './Destination.tsx';
import { Field, Notice, ReadFeedback, SectionHeading, StateBadge } from './components.tsx';
import { canExecute, configurationKey, confirmationPhrase, emptyConfiguration, isRecord, isTerminal, safeWebUrl } from './domain.ts';
import { useRead } from './hooks.ts';
import { useLive } from './live.ts';
import type { Configuration, Container, DatabaseDiscovery, Identity, Plan, Run, Status } from './types.ts';

const stages = [
  { title: 'Source', icon: Database24Regular, description: 'Discover your local database' },
  { title: 'Azure destination', icon: Cloud24Regular, description: 'Choose exact cloud resources' },
  { title: 'Review', icon: DocumentBulletList24Regular, description: 'Inspect the immutable plan' },
  { title: 'Migrate', icon: Play24Regular, description: 'Approve and follow execution' },
  { title: 'Verify', icon: ShieldCheckmark24Regular, description: 'Inspect live validation evidence' },
];

export function App() {
  const [stage, setStage] = useState(0);
  const [configuration, setConfiguration] = useState<Configuration>({ ...emptyConfiguration });
  const configurationRef = useRef(configuration);
  const status = useRead<Status>('/api/status');
  const containers = useRead<Container[]>('/api/discovery/containers');
  const live = useLive();
  const [discovery, setDiscovery] = useState<{ containerName: string; data: DatabaseDiscovery }>();
  const [discovering, setDiscovering] = useState(false);
  const [discoveryError, setDiscoveryError] = useState('');
  const [plan, setPlan] = useState<Plan>();
  const [reviewIdentity, setReviewIdentity] = useState<Identity>();
  const [planning, setPlanning] = useState(false);
  const [planError, setPlanError] = useState('');
  const [phrase, setPhrase] = useState('');
  const [writersStopped, setWritersStopped] = useState(false);
  const [run, setRun] = useState<Run>();
  const [executing, setExecuting] = useState(false);
  const [executionAttempted, setExecutionAttempted] = useState(false);
  const [runError, setRunError] = useState('');
  const [cancelling, setCancelling] = useState(false);
  const [cancelRequested, setCancelRequested] = useState(false);
  const [recoverId, setRecoverId] = useState('');
  const [recovering, setRecovering] = useState(false);
  const [pollRevision, setPollRevision] = useState(0);
  const executionLock = useRef(false);
  const planLock = useRef(false);
  const discoveryLock = useRef(false);
  const cancelLock = useRef(false);
  const [copilotVisible, setCopilotVisible] = useState(true);
  const [eventFilter, setEventFilter] = useState<'all' | 'run'>('all');
  const stageSection = useRef<HTMLElement>(null);
  const stageNavigation = useRef<HTMLElement>(null);
  const previousStage = useRef(stage);
  useEffect(() => {
    if (stage === previousStage.current) return;
    previousStage.current = stage;
    stageNavigation.current?.querySelector('[aria-current="step"]')?.scrollIntoView({ block: 'nearest', inline: 'center' });
    stageSection.current?.focus({ preventScroll: true });
    stageSection.current?.scrollIntoView({ block: 'start' });
  }, [stage]);
  const sourceSelected = !!configuration.containerName && !!configuration.sourceDatabase;
  const planValid = plan !== undefined && configurationKey(plan.configuration) === configurationKey(configuration);
  const activeRun = !!run && !isTerminal(run.state);
  const source = containers.data?.find(item => item.name === configuration.containerName);
  const sourceDiscovery = discovery?.containerName === configuration.containerName ? discovery.data : undefined;
  const sourceDatabase = sourceDiscovery?.databases.find(item => item.name === configuration.sourceDatabase);
  const selectedStep = stages[stage];

  function change(patch: Partial<Configuration>) {
    if (executionAttempted || planning) return;
    const updated = { ...configurationRef.current, ...patch };
    configurationRef.current = updated;
    setConfiguration(updated);
    setPlan(undefined);
    setPlanError('');
    setPhrase('');
    setWritersStopped(false);
    setReviewIdentity(undefined);
  }
  async function discover() {
    if (!configuration.containerName || discoveryLock.current) return;
    const containerName = configuration.containerName;
    discoveryLock.current = true;
    setDiscovering(true);
    setDiscoveryError('');
    change({ sourceDatabase: '' });
    setDiscovery(undefined);
    try {
      const data = await post<DatabaseDiscovery>('/api/discovery/databases', { containerName });
      if (configurationRef.current.containerName === containerName) setDiscovery({ containerName, data });
    } catch (error) { setDiscoveryError(errorMessage(error)); }
    finally { setDiscovering(false); discoveryLock.current = false; }
  }
  async function prepareReview(identity: Identity) {
    if (planLock.current) return;
    planLock.current = true;
    setPlanning(true);
    setPlanError('');
    const captured = { ...configurationRef.current };
    try {
      const result = await post<Plan>('/api/plans', captured);
      if (!result?.id || !result.fingerprint || result.state !== 'review' || !result.configuration
        || configurationKey(result.configuration) !== configurationKey(captured)) {
        throw new Error('The server did not return a matching review plan. Nothing can be executed. Check the backend response.');
      }
      if (configurationKey(configurationRef.current) === configurationKey(captured)) {
        setPlan(result);
        setReviewIdentity(identity);
        setPhrase('');
        setWritersStopped(false);
        setStage(2);
      }
    } catch (error) { setPlanError(errorMessage(error)); }
    finally { setPlanning(false); planLock.current = false; }
  }
  async function execute() {
    if (!plan || !canExecute(phrase, writersStopped, configuration, plan.configuration) || executionLock.current) return;
    executionLock.current = true;
    setExecutionAttempted(true);
    setExecuting(true);
    setRunError('');
    setStage(3);
    try {
      const result = await post<Run>(`/api/plans/${encodeURIComponent(plan.id)}/run`, { confirmation: confirmationPhrase, writersStopped: true });
      if (!result?.id || typeof result.state !== 'string' || !Array.isArray(result.steps)) {
        throw new Error('The run request returned no usable run identity. Its outcome is unknown. Recover the run ID from the local service; do not repeat provisioning.');
      }
      setRun(result);
    } catch (error) {
      setRunError(errorMessage(error));
      // Only a definitive client rejection permits a deliberate corrected retry.
      if (error instanceof ApiError && error.status >= 400 && error.status < 500 && ![408, 409].includes(error.status)) {
        executionLock.current = false;
        setExecutionAttempted(false);
        setWritersStopped(false);
        setPhrase('');
      }
    } finally { setExecuting(false); }
  }
  useEffect(() => {
    if (!run?.id || isTerminal(run.state)) return;
    let timer: ReturnType<typeof setTimeout>;
    const controller = new AbortController();
    const id = run.id;
    async function poll() {
      try {
        const next = await get<Run>(`/api/runs/${encodeURIComponent(id)}`, controller.signal);
        if (controller.signal.aborted) return;
        if (next.id !== id || typeof next.state !== 'string' || !Array.isArray(next.steps)) throw new Error('The service returned an invalid or mismatched run. Monitoring has stopped.');
        setRun(next);
        setRunError('');
        if (!isTerminal(next.state)) timer = setTimeout(() => { void poll(); }, 2500);
      } catch (error) {
        if (!controller.signal.aborted) setRunError(`${errorMessage(error)} Automatic run monitoring paused; retry the read to reconnect.`);
      }
    }
    void poll();
    return () => { controller.abort(); clearTimeout(timer); };
  }, [run?.id, run ? isTerminal(run.state) : false, pollRevision]);

  async function cancel() {
    if (!run || cancelLock.current || cancelRequested) return;
    cancelLock.current = true;
    setCancelling(true);
    setRunError('');
    try {
      await post<unknown>(`/api/runs/${encodeURIComponent(run.id)}/cancel`, {});
      setCancelRequested(true);
      setPollRevision(value => value + 1);
    } catch (error) {
      setRunError(`Cancellation request: ${errorMessage(error)} Inspect run state before retrying.`);
    } finally { setCancelling(false); cancelLock.current = false; }
  }
  async function recoverRun() {
    if (!recoverId.trim() || recovering) return;
    setRecovering(true);
    setRunError('');
    try {
      const result = await get<Run>(`/api/runs/${encodeURIComponent(recoverId.trim())}`);
      if (result?.id !== recoverId.trim() || typeof result.state !== 'string' || !Array.isArray(result.steps)) throw new Error('The local API did not return the requested run.');
      executionLock.current = true;
      setExecutionAttempted(true);
      setRun(result);
      setCancelRequested(false);
      setStage(3);
      setPollRevision(value => value + 1);
    } catch (error) { setRunError(errorMessage(error)); }
    finally { setRecovering(false); }
  }
  const visibleEvents = eventFilter === 'run' ? live.events.filter(event => event.runId === run?.id) : live.events;
  const serviceDeskUrl = status.data ? safeWebUrl(status.data.serviceDeskUrl) : undefined;
  return <div className="studio">
    <a href="#main-content" className="skip-link">Skip to migration workspace</a>
    <header className="topbar">
      <a className="brand" href="#main-content"><span className="brand-mark"><Database24Regular /></span><span>AI Migration <strong>Studio</strong></span></a>
      <div className="topbar-context"><span className="context-divider" /><Cloud24Regular /><span>Azure SQL</span><span className="local-pill">LOCAL WORKSPACE</span></div>
      <div className="topbar-actions"><span className="connection-indicator" data-connected={!!status.data}><span />{status.data ? 'Local API connected' : status.loading ? 'Connecting to API' : 'API not connected'}</span>
        <Button appearance="subtle" className="copilot-toggle" icon={<Sparkle24Regular />} onClick={() => setCopilotVisible(value => !value)} aria-expanded={copilotVisible}>Copilot</Button></div>
    </header>
    <div className={`studio-layout ${copilotVisible ? '' : 'without-copilot'}`}>
      <aside className="navigation" aria-label="Studio navigation">
        <div className="workspace-label">MIGRATION WORKSPACE</div>
        <div className="workspace-name"><div className="workspace-icon"><Cloud24Regular /></div><div>Local to cloud<span>Azure SQL Database</span></div></div>
        <nav className="side-stages" aria-label="Migration stages">{stages.map((item, index) => {
          const Icon = item.icon;
          const allowed = index === 0 || (index === 1 && sourceSelected && !executionAttempted) || (index === 2 && planValid) || (index === 3 && (planValid || !!run || executionAttempted)) || (index === 4 && !!run);
          return <button key={item.title} aria-label={item.title} disabled={!allowed || planning || executing} onClick={() => setStage(index)} aria-current={index === stage ? 'step' : undefined}>
            <Icon /><span>{item.title}</span><span className="nav-number">{String(index + 1).padStart(2, '0')}</span>
          </button>;
        })}</nav>
        <div className="sidebar-bottom"><ShieldCheckmark24Regular /><h3>Deliberate by design.</h3><p>Your source stays in place. Cloud actions require an exact, explicit approval.</p>
          {serviceDeskUrl && <a href={serviceDeskUrl} target="_blank" rel="noreferrer">Open existing Service Desk <Open24Regular /></a>}
          <div className="sidebar-footer">No application cutover</div>
        </div>
      </aside>
      <main id="main-content" className="main" tabIndex={-1}>
        <nav ref={stageNavigation} className="stepper" aria-label="Persistent migration progress"><ol>{stages.map((item, index) => {
          const allowed = index === 0 || (index === 1 && sourceSelected && !executionAttempted) || (index === 2 && planValid) || (index === 3 && (planValid || !!run || executionAttempted)) || (index === 4 && !!run);
          return <li key={item.title} className={index === stage ? 'current' : ''}><button aria-current={index === stage ? 'step' : undefined} disabled={!allowed || planning || executing} onClick={() => setStage(index)}>
            <span className="step-number">{index + 1}</span><span>{item.title}</span>
          </button></li>;
        })}</ol></nav>
        <div className="workspace-content">
          {stage !== 0 && <><div className="page-intro"><div><div className="eyebrow">AZURE SQL / GUIDED MIGRATION</div><h1>From local.<br className="mobile-only" /> To possibility.</h1><p>A clear path to Azure, with evidence at every step.</p></div><div className="intro-icon" aria-hidden="true"><Cloud24Regular /></div></div>
          <div className="journey-card" aria-label="Source to destination">
            <div className="journey-node"><div className="journey-icon source-icon"><Database24Regular /></div><div><span className="overline">LOCAL SOURCE</span><strong>{configuration.sourceDatabase || 'Choose a database'}</strong><span>{source?.endpoint || sourceDiscovery?.endpoint || 'No source connected'}</span></div></div>
            <div className="journey-path" aria-hidden="true"><span /><ArrowRight24Regular /><span /></div>
            <div className="journey-node"><div className="journey-icon target-icon"><Cloud24Regular /></div><div><span className="overline">AZURE DESTINATION</span><strong>{configuration.targetDatabase || 'Your new Azure SQL database'}</strong><span>{configuration.serverName || 'Destination not selected'}</span></div></div>
          </div></>}
          <section ref={stageSection} tabIndex={-1} className="stage-card" aria-label={selectedStep.description}>
            {stage === 0 && <>
              <SectionHeading eyebrow="STEP 1 OF 5 / SOURCE" title="Choose your local database">Select a container, list its databases, then choose the database to migrate. Nothing is changed in this step.</SectionHeading>
              <p className="source-next" role="status">{!configuration.containerName ? 'Start here: choose your running container below.' : !sourceDiscovery ? 'Next: click List databases to see what is inside this container.' : !configuration.sourceDatabase ? 'Next: choose a database from the list below.' : `Ready: ${configuration.sourceDatabase} selected. Continue to Azure destination.`}</p>
              <fieldset className="plain-fieldset" disabled={discovering || executionAttempted}>
                <Field label="1. Local container"><select value={configuration.containerName} disabled={containers.loading} onChange={event => {
                  change({ containerName: event.target.value, sourceDatabase: '' }); setDiscovery(undefined); setDiscoveryError('');
                }}><option value="">Select a discovered container</option>{containers.data?.map(item => <option key={item.name} value={item.name}>{item.name} · {item.endpoint} · {item.state}</option>)}</select></Field>
                <ReadFeedback {...containers} retry={containers.reload} empty={containers.data?.length === 0 ? 'No containers found. Start or authorize access to your intended source, then refresh discovery.' : undefined} />
                <div className="inline-actions"><Button appearance={sourceDiscovery ? 'secondary' : 'primary'} icon={<Database24Regular />} onClick={() => { void discover(); }} disabled={!configuration.containerName || discovering}>{discovering ? 'Listing databases…' : '2. List databases'}</Button><Button appearance="subtle" onClick={containers.reload} disabled={containers.loading}>Refresh containers</Button></div>
                {discoveryError && <Notice title="Database discovery failed" danger>{discoveryError} Check local access and source permissions, then explicitly retry discovery.</Notice>}
                {sourceDiscovery && <><Field label="3. Database to migrate"><select value={configuration.sourceDatabase} onChange={event => change({ sourceDatabase: event.target.value })}><option value="">Select a database</option>
                  {sourceDiscovery.databases.map(database => <option key={database.name} value={database.name}>{database.name}</option>)}</select></Field>
                  {sourceDiscovery.databases.length === 0 && <Notice title="No databases returned">Confirm the backend credential is authorized to discover the intended database.</Notice>}</>}
                {sourceDatabase && <div className="source-stats"><div><strong>{sourceDatabase.tableCount.toLocaleString()}</strong><span>tables reported</span></div>{sourceDatabase.caseCount !== undefined && <div><strong>{sourceDatabase.caseCount.toLocaleString()}</strong><span>cases reported</span></div>}<div><ShieldCheckmark24Regular /><span>Source unchanged</span></div></div>}
              </fieldset>
              <div className="stage-actions"><span className="muted">{sourceSelected ? 'Source selected. Choose where it will go next.' : 'Select a database to continue.'}</span><Button appearance={sourceSelected ? 'primary' : 'secondary'} icon={<ArrowRight24Regular />} iconPosition="after" disabled={!sourceSelected || executionAttempted || discovering} onClick={() => setStage(1)}>Next: Azure destination</Button></div>
              <details className="source-technical"><summary>Connection details &amp; migration prerequisites</summary>
                {source && <dl className="facts source-facts"><dt>Container image</dt><dd className="mono">{source.image}</dd><dt>Endpoint</dt><dd>{source.endpoint}</dd><dt>Container state</dt><dd><StateBadge state={source.state} /></dd></dl>}
                <p>Credentials stay in the backend. No password or connection string is collected in the browser.</p>
                <p>Read-only mode is not needed to list databases. Before actual migration, all writers must be stopped and the source must already be READ_ONLY through a separately approved action. This app does not change source mode; the backend blocks export of a writable source.</p>
              </details>
            </>}
            {stage === 1 && <><Button appearance="subtle" icon={<ArrowLeft24Regular />} disabled={planning} onClick={() => setStage(0)}>Back to source</Button><Destination configuration={configuration} change={change} review={identity => { void prepareReview(identity); }} pending={planning} error={planError} /></>}
            {stage === 2 && planValid && plan && <>
              <SectionHeading eyebrow="03 / Review" title="Every choice, in the open.">This server-generated review is bound to the exact configuration below. Editing any choice invalidates it.</SectionHeading>
              <div className="review-heading"><StateBadge state="review" /><span className="mono">Plan {plan.id}</span></div>
              <dl className="facts review-facts">
                <dt>Source container</dt><dd>{plan.configuration.containerName}</dd><dt>Source database</dt><dd>{plan.configuration.sourceDatabase} · unchanged</dd>
                <dt>Tenant ID</dt><dd className="mono">{plan.configuration.tenantId}</dd><dt>Subscription ID</dt><dd className="mono">{plan.configuration.subscriptionId}</dd><dt>Region</dt><dd>{plan.configuration.region}</dd>
                <dt>Resource group</dt><dd>{plan.configuration.resourceGroup} <span className="choice-tag">{plan.configuration.createResourceGroup ? 'Create new' : 'Use existing'}</span></dd>
                <dt>Logical server</dt><dd>{plan.configuration.serverName} <span className="choice-tag">{plan.configuration.createServer ? 'Create new' : 'Use existing'}</span></dd>
                <dt>Target database</dt><dd>{plan.configuration.targetDatabase} · new and empty only</dd><dt>Authentication</dt><dd>Microsoft Entra · current user administrator</dd>
                <dt>Administrator</dt><dd>{reviewIdentity?.name || 'Not reported'}<br />{reviewIdentity?.userPrincipalName}<br /><span className="mono">{reviewIdentity?.id}</span></dd>
                <dt>Created</dt><dd>{plan.createdAt}</dd><dt>Fingerprint</dt><dd className="mono">{plan.fingerprint}</dd>
              </dl>
              <h3>Backend operation summary</h3><ul className="summary-list">{plan.summary.map((item, index) => <li key={index}>{item}</li>)}</ul>
              <div className="safety-grid"><div><ShieldCheckmark24Regular /><h3>Free protection</h3><p>Require <code>useFreeLimit=true</code> and <code>AutoPause</code> before and after import. No paid overages or tier fallback. Other resources may have costs; the free offer is not an unlimited guarantee.</p></div>
                <div><Database24Regular /><h3>Offline consistency gate</h3><p>ALL writers must be quiesced and the source must already be READ_ONLY through a separately approved operational action. A checkbox alone is not proof; a writable source must be blocked by the backend.</p></div></div>
              <Notice title="Source and network remain untouched">Migration does not stop applications, change the source to read-only, alter source data or schema, or create firewall rules. Existing narrowly scoped connectivity is required. No administrator replacement or authentication change without separate approval.</Notice>
              <Notice title="No application cutover">The existing Service Desk configuration stays unchanged. Cutover is a separate approved step and is not implemented here.</Notice>
              <details className="planned-steps"><summary>Planned operation steps</summary><StepList steps={plan.steps} /></details>
              <div className="stage-actions"><Button icon={<ArrowLeft24Regular />} disabled={executionAttempted} onClick={() => setStage(1)}>Edit destination</Button><Button appearance="primary" icon={<ArrowRight24Regular />} iconPosition="after" onClick={() => setStage(3)}>Continue to explicit approval</Button></div>
            </>}
            {stage === 3 && <>
              <SectionHeading eyebrow="04 / Migrate" title={run ? 'Follow the real work.' : 'You hold the final gate.'}>{run ? 'Live run status from the local backend. No estimated or simulated success.' : 'This action creates Azure resources and starts an offline BACPAC migration. Development and plan approval do not authorize execution.'}</SectionHeading>
              {!run && planValid && plan && !executionAttempted && <div className="execution-gate">
                <Notice title="Cloud action · explicit approval required">Plan {plan.id} → {plan.configuration.serverName} / {plan.configuration.targetDatabase}. Revisit Review to inspect the exact resources before proceeding.</Notice>
                <Notice title="READ_ONLY consistency gate + scoped connectivity required">The source must already be READ_ONLY and ALL writers quiesced through a separately approved action. The checkbox alone is insufficient; the host refuses writable sources. Existing target firewall access must be narrowly scoped and configured separately. No clients are stopped, no source mode is changed, and no broad firewall rule is created.</Notice>
                <Checkbox checked={writersStopped} onChange={(_, data) => setWritersStopped(data.checked === true)} label="I confirm ALL WRITERS are quiesced, not just the app closed, and the source is already READ_ONLY via a separately approved action. I understand the backend must independently verify this." />
                <Field label={`Type exactly: ${confirmationPhrase}`}><input className="confirmation-input" autoComplete="off" spellCheck={false} value={phrase} onChange={event => setPhrase(event.target.value)} /></Field>
                <p>Agent-assisted, host-executed. The host—not the chat model—executes this explicitly approved migration. Free-offer AutoPause protection is mandatory. Source unchanged. No firewall creation. No app cutover.</p>
                <div className="stage-actions"><Button icon={<ArrowLeft24Regular />} onClick={() => setStage(2)}>Revisit Review</Button><Button appearance="primary" icon={<Play24Regular />} disabled={!canExecute(phrase, writersStopped, configuration, plan.configuration) || executing} onClick={() => { void execute(); }}>Create free database &amp; migrate</Button></div>
              </div>}
              {executing && <div className="loading" role="status"><Spinner size="tiny" /> Submitting your explicitly approved run once…</div>}
              {runError && <Notice title="Execution / monitoring needs attention" danger><p>{runError}</p>{run && <Button onClick={() => setPollRevision(value => value + 1)}>Retry run status (read-only)</Button>}</Notice>}
              {run && <><div className="run-heading"><div><span className="eyebrow">RUN ID</span><p className="mono">{run.id}</p></div><StateBadge state={run.state} /></div>
                {activeRun && !runError && <div className="run-progress"><ProgressBar aria-label="Migration in progress, percentage unknown" /><p>In progress · waiting for reported evidence</p></div>}
                {run.error && <Notice title="Backend reported a run error" danger>{run.error}</Notice>}
                <StepList steps={run.steps} />
                {cancelRequested && <Notice title="Cancellation requested, not yet confirmed">Resources and partial target state may remain. Do not resume writes until the backend confirms work has stopped. No automatic deletion is promised.</Notice>}
                <div className="stage-actions"><Button disabled={!activeRun || cancelling || cancelRequested} onClick={() => { void cancel(); }}>{cancelling ? 'Requesting cancellation…' : cancelRequested ? 'Cancellation requested' : 'Request safe cancellation'}</Button><Button appearance="primary" onClick={() => setStage(4)}>Inspect validation evidence</Button></div></>}
              {!run && !executing && <details className="recovery" open={executionAttempted || undefined}><summary>Recover run state · never repeat automatically</summary><p>If a request outcome is unknown, obtain its run ID from the local service and read its state before taking another action.</p><Field label="Existing run ID"><input value={recoverId} onChange={event => setRecoverId(event.target.value)} /></Field><Button disabled={!recoverId.trim() || recovering} onClick={() => { void recoverRun(); }}>Read existing run</Button></details>}
            </>}
            {stage === 4 && run && <>
              <SectionHeading eyebrow="05 / Verify" title="Evidence. Not assumptions.">Validation is shown exactly as returned by the backend. A completed import alone does not prove feature fidelity.</SectionHeading>
              <div className="run-heading"><span className="mono">Run {run.id}</span><StateBadge state={run.state} /></div>
              {run.error && <Notice title="Run error" danger>{run.error}</Notice>}
              {run.validation && Object.keys(run.validation).length > 0 ? <Validation value={run.validation} /> : <Notice title="Validation has not been reported">Row counts, source/target fidelity, masks, JSON, vectors, indexes, and restricted-runtime checks remain unverified until the backend returns evidence.</Notice>}
              {runError && <Notice title="Run monitoring paused" danger>{runError}</Notice>}
              <div className="inline-actions"><Button disabled={recovering} onClick={() => { setRecoverId(run.id); void get<Run>(`/api/runs/${encodeURIComponent(run.id)}`).then(result => { if (result.id !== run.id || !Array.isArray(result.steps)) throw new Error('Mismatched run response.'); setRun(result); setRunError(''); }).catch(error => setRunError(errorMessage(error))); }}>Refresh evidence (read-only)</Button><Button onClick={() => setStage(3)}>Execution details</Button></div>
              <div className="cutover-card"><div className="card-title"><ShieldCheckmark24Regular /><h3>Application cutover</h3></div><p>Existing Service Desk remains untouched. Updating application configuration requires a separate approval, runtime principal verification, health check, and rollback plan.</p><Button disabled>Separate approved step · not implemented</Button></div>
            </>}
          </section>
          {status.error && <Notice title="Migration readiness check failed" danger><p>{status.error}</p><Button onClick={status.reload}>Retry readiness</Button></Notice>}
          <details className="readiness source-readiness"><summary><PlugConnected24Regular /> Migration readiness <span>{status.loading ? 'Checking in background' : status.data ? `${status.data.capabilities.filter(item => item.state === 'ready').length} / ${status.data.capabilities.length} ready` : 'Not verified'}</span></summary>
            <p>These checks apply before migration. You can select your source while they finish.</p>
            {status.data && <div className="readiness-list">{status.data.capabilities.map(item => <div key={item.name}><div><strong>{item.name}</strong><StateBadge state={item.state} /></div><p>{item.detail}</p></div>)}</div>}
            <Button onClick={status.reload}>Refresh readiness</Button>
          </details>
          <details className="activity-card" aria-label="Live operation activity" open={stage !== 0 || undefined}><summary>Technical activity <StateBadge state={live.connection} /></summary>
            {live.streamError && <Notice title="Event stream status" danger>{live.streamError}</Notice>}
            <div className="activity-toolbar"><label className="field"><span>Show events</span><select value={eventFilter} onChange={event => setEventFilter(event.target.value === 'run' ? 'run' : 'all')}><option value="all">All session activity</option><option value="run" disabled={!run}>Current run only</option></select></label><Button onClick={live.reconnect}>Reconnect stream</Button></div>
            <div className="activity-log" role="log" aria-label="Latest server events" tabIndex={0} aria-live="off">
              {!visibleEvents.length && <div className="log-empty"><PlugConnected24Regular /><p>{live.connection === 'connected' ? 'Listening. No matching server activity received yet.' : 'No activity available. Connect to the local event stream.'}</p></div>}
              {visibleEvents.map(event => <div className="log-line" key={event.id}><time dateTime={event.time}>{event.time}</time><div><strong>{event.stage}</strong><StateBadge state={event.state} /><p>{event.message}</p>{event.runId && <span className="mono">Run {event.runId}</span>}</div></div>)}
            </div><p className="log-caption">Latest 500 server events retained in memory. Tool activity and loaded skill metadata are separate.</p>
          </details>
          <footer className="workspace-footer"><ShieldCheckmark24Regular /> Local-first workspace. Explicit approvals. Verifiable outcomes.</footer>
        </div>
      </main>
      {copilotVisible && <Copilot status={status.data} live={live} stage={stage} />}
    </div>
  </div>;
}

function StepList({ steps }: { steps: Run['steps'] }) {
  if (!steps.length) return <p className="muted">No operation steps reported.</p>;
  return <ol className="operation-steps">{steps.map(step => <li key={step.id}><div className="operation-icon">{['completed', 'succeeded', 'passed'].includes(step.state.toLowerCase()) ? <Checkmark24Regular /> : <span aria-hidden="true" />}</div><div><div className="operation-title"><h3>{step.title}</h3><StateBadge state={step.state} /></div><p>{step.message || 'No detail reported.'}</p></div></li>)}</ol>;
}
function Validation({ value }: { value: Record<string, unknown> }) {
  return <div className="validation-evidence">{Object.entries(value).map(([key, evidence]) => <details key={key} open><summary>{key}</summary>
    {isRecord(evidence) && typeof evidence.state === 'string' && <StateBadge state={evidence.state} />}
    <pre>{typeof evidence === 'string' ? evidence : JSON.stringify(evidence, null, 2)}</pre>
  </details>)}</div>;
}

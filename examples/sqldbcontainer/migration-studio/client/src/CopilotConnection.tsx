import { useEffect, useState } from 'react';
import { Button, Spinner } from '@fluentui/react-components';
import { errorMessage, get, post } from './api.ts';
import { Notice, StateBadge } from './components.tsx';
import type { CopilotSignIn, Status } from './types.ts';

export function CopilotConnection({ status, error, onCheck }: {
  status?: Status['copilot']; error?: string; onCheck: () => void;
}) {
  const [attempt, setAttempt] = useState<CopilotSignIn>();
  const [failure, setFailure] = useState('');
  const [action, setAction] = useState(false);
  const waiting = attempt?.state === 'waiting';
  const connected = status?.authenticated === true;

  useEffect(() => {
    const controller = new AbortController();
    void get<CopilotSignIn>('/api/copilot/signin', controller.signal)
      .then(value => { if (!controller.signal.aborted) setAttempt(value); })
      .catch(cause => { if (!controller.signal.aborted) setFailure(errorMessage(cause)); });
    return () => controller.abort();
  }, []);

  useEffect(() => {
    if (!waiting || action || failure) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      void get<CopilotSignIn>('/api/copilot/signin', controller.signal).then(value => {
        if (controller.signal.aborted) return;
        setAttempt(value);
        if (value.state === 'connected') onCheck();
      }).catch(cause => { if (!controller.signal.aborted) setFailure(errorMessage(cause)); });
    }, 2000);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [attempt, waiting, action, failure, onCheck]);

  async function connect() {
    setAction(true);
    setFailure('');
    try {
      const value = await post<CopilotSignIn>('/api/copilot/signin', {});
      setAttempt(value);
      if (value.state === 'connected') onCheck();
    } catch (cause) { setFailure(errorMessage(cause)); }
    finally { setAction(false); }
  }
  async function cancel() {
    if (!attempt?.id) return;
    setAction(true);
    setFailure('');
    try { setAttempt(await post<CopilotSignIn>(`/api/copilot/signin/${encodeURIComponent(attempt.id)}/cancel`, {})); }
    catch (cause) { setFailure(errorMessage(cause)); }
    finally { setAction(false); }
  }
  async function check() {
    setAction(true);
    setFailure('');
    try {
      setAttempt(await get<CopilotSignIn>('/api/copilot/signin'));
      onCheck();
    } catch (cause) { setFailure(errorMessage(cause)); }
    finally { setAction(false); }
  }

  return <section className="copilot-connection" aria-label="Copilot connection">
    <div className="connection-heading"><strong>Copilot connection</strong><StateBadge state={connected ? 'connected' : waiting ? 'waiting' : 'not connected'} /></div>
    {!connected && !waiting && <p>Connect this app to your GitHub Copilot account. This is separate from Azure and VS Code sign-in.</p>}
    {connected && <p>Signed in. Start the guide when ready; sign-in itself does not run inference.</p>}
    {!connected && waiting && <>
      <p>1. Copy this one-time code:</p>
      <code className="signin-code" aria-label="GitHub one-time code">{attempt.userCode}</code>
      <p>2. <a href={attempt.verificationUri} target="_blank" rel="noopener noreferrer">Open GitHub to authorize Copilot</a>, then enter the code.</p>
      <p role="status"><Spinner size="tiny" /> Waiting for GitHub confirmation. This pane updates automatically.</p>
      {attempt.expiresAt && <p className="muted">Code expires at {new Date(attempt.expiresAt).toLocaleTimeString()}.</p>}
    </>}
    {!connected && attempt && !['idle', 'waiting'].includes(attempt.state) && <Notice title={attempt.state === 'failed' ? 'Copilot sign-in failed' : 'Copilot sign-in'} danger={attempt.state === 'failed'}>{attempt.message}</Notice>}
    {(failure || error) && <Notice title="Copilot connection check failed" danger>{failure || error}</Notice>}
    <div className="inline-actions">
      {!connected && !waiting && <Button appearance="primary" disabled={action || !status} onClick={() => void connect()}>{action ? 'Connecting…' : 'Connect Copilot'}</Button>}
      {waiting && <Button disabled={action} onClick={() => void cancel()}>Cancel sign-in</Button>}
      <Button disabled={action} onClick={() => void check()}>{waiting ? 'Check sign-in status' : 'Check connection'}</Button>
    </div>
    {!connected && status && !waiting && <p className="muted">{status.status}</p>}
  </section>;
}

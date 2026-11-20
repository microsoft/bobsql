import type { ReactNode } from 'react';
import { Badge, Button, Spinner } from '@fluentui/react-components';

export function Notice({ title, children, danger = false }: { title: string; children?: ReactNode; danger?: boolean }) {
  return <div className={`notice ${danger ? 'danger' : ''}`} role={danger ? 'alert' : 'status'}>
    <strong>{title}</strong>{children && <div>{children}</div>}
  </div>;
}
export function ReadFeedback({ loading, error, retry, empty }: { loading: boolean; error?: string; retry: () => void; empty?: string }) {
  if (loading) return <div className="loading" role="status"><Spinner size="tiny" /> Loading from local service…</div>;
  if (error) return <Notice title="Not connected / request failed" danger><p>{error}</p><Button onClick={retry}>Retry read-only request</Button></Notice>;
  return empty ? <p className="empty-note">{empty}</p> : null;
}
export function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  // Native controls are wrapped by a label for an accessible name without generated IDs.
  return <label className="field"><span>{label}</span>{children}{hint && <span className="field-hint">{hint}</span>}</label>;
}
export function StateBadge({ state }: { state: string }) {
  const normalized = state.toLowerCase();
  const color = ['ready', 'completed', 'succeeded', 'verified', 'passed', 'connected'].includes(normalized) ? 'success'
    : ['blocked', 'failed', 'error', 'disconnected'].includes(normalized) ? 'danger'
    : ['running', 'inprogress', 'in_progress', 'connecting'].includes(normalized) ? 'brand' : 'informative';
  return <Badge appearance="tint" color={color} className="state-badge">{state.replaceAll('_', ' ')}</Badge>;
}
export function SectionHeading({ eyebrow, title, children }: { eyebrow: string; title: string; children: ReactNode }) {
  return <div className="section-heading"><span className="eyebrow">{eyebrow}</span><h2>{title}</h2><p>{children}</p></div>;
}

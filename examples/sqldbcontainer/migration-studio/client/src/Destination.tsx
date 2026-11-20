import { useEffect, useState } from 'react';
import { Button, Checkbox, Combobox, Option, Switch } from '@fluentui/react-components';
import { ArrowRight24Regular, Person24Regular } from '@fluentui/react-icons';
import { Field, Notice, ReadFeedback, SectionHeading } from './components.tsx';
import { useRead } from './hooks.ts';
import type { Configuration, Identity, Location, ResourceGroup, Server, Subscription, Tenant } from './types.ts';

type Props = {
  configuration: Configuration;
  change: (patch: Partial<Configuration>) => void;
  review: (identity: Identity) => void;
  pending: boolean;
  error: string;
};
export function Destination({ configuration: c, change, review, pending, error }: Props) {
  const [identityConfirmed, setIdentityConfirmed] = useState(false);
  const [subscriptionSearch, setSubscriptionSearch] = useState('');
  const q = encodeURIComponent;
  const tenants = useRead<Tenant[]>('/api/azure/tenants');
  const subscriptions = useRead<Subscription[]>(c.tenantId ? `/api/azure/subscriptions?tenantId=${q(c.tenantId)}` : null);
  const azureContext = c.tenantId && c.subscriptionId ? `tenantId=${q(c.tenantId)}&subscriptionId=${q(c.subscriptionId)}` : null;
  const locations = useRead<Location[]>(azureContext && c.createServer ? `/api/azure/locations?${azureContext}` : null);
  const groups = useRead<ResourceGroup[]>(azureContext ? `/api/azure/groups?${azureContext}` : null);
  const servers = useRead<Server[]>(c.subscriptionId && c.resourceGroup && !c.createResourceGroup && !c.createServer
    ? `/api/azure/servers?${azureContext}&resourceGroup=${q(c.resourceGroup)}` : null);
  const identity = useRead<Identity>(azureContext ? `/api/azure/identity?${azureContext}` : null);
  useEffect(() => { setIdentityConfirmed(false); }, [c.tenantId, c.subscriptionId, identity.data?.id]);
  const selectedSubscription = subscriptions.data?.find(item => item.id === c.subscriptionId);
  const matchingSubscriptions = subscriptions.data?.filter(item =>
    `${item.name} ${item.id}`.toLowerCase().includes(subscriptionSearch.trim().toLowerCase())) ?? [];

  const valid = !!(
    tenants.data?.some(item => item.id === c.tenantId)
    && subscriptions.data?.some(item => item.id === c.subscriptionId)
    && (c.createServer ? locations.data?.some(item => item.id === c.region) : servers.data?.some(item => item.name === c.serverName && item.region === c.region))
    && (c.createResourceGroup ? /^[\w.()-]{1,90}$/.test(c.resourceGroup) && !c.resourceGroup.endsWith('.') : groups.data?.some(item => item.name === c.resourceGroup))
    && (c.createServer ? /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(c.serverName) : servers.data?.some(item => item.name === c.serverName))
    && c.targetDatabase.trim() && c.targetDatabase.length <= 128
    && identity.data?.id && identityConfirmed && !identity.loading && !identity.error
  );
  return <>
    <SectionHeading eyebrow="02 / Azure destination" title="A new home in Azure">
      Choose the exact destination. Discovery is read-only; nothing is provisioned here.
    </SectionHeading>
    <fieldset disabled={pending} className="plain-fieldset">
      <div className="form-grid">
        <div><Field label="Directory / tenant"><select value={c.tenantId} onChange={event => { setSubscriptionSearch(''); change({
          tenantId: event.target.value, subscriptionId: '', region: '', resourceGroup: '', serverName: '', createResourceGroup: false, createServer: false,
        }); }}><option value="">Select a tenant</option>{tenants.data?.map(item => <option key={item.id} value={item.id}>{item.name} · {item.id}</option>)}</select></Field>
          <ReadFeedback {...tenants} retry={tenants.reload} empty={tenants.data?.length === 0 ? 'No tenants returned. Sign in through the local backend and retry.' : undefined} /></div>
        <div><div className="field"><label htmlFor="subscription-picker">Subscription</label>
          <Combobox id="subscription-picker" className="subscription-picker" size="large" aria-describedby="subscription-search-hint"
            listbox={{ className: 'subscription-results' }}
            placeholder="Type a subscription name or ID"
            disabled={!c.tenantId || subscriptions.loading || pending}
            value={selectedSubscription ? `${selectedSubscription.name} · ${selectedSubscription.id}` : subscriptionSearch}
            selectedOptions={selectedSubscription ? [selectedSubscription.id] : []}
            onChange={event => {
              setSubscriptionSearch(event.target.value);
              if (c.subscriptionId) change({ subscriptionId: '', region: '', resourceGroup: '', serverName: '', createResourceGroup: false, createServer: false });
            }}
            onOptionSelect={(_, data) => {
              if (!subscriptions.data?.some(item => item.id === data.optionValue)) return;
              setSubscriptionSearch('');
              change({ subscriptionId: data.optionValue, region: '', resourceGroup: '', serverName: '', createResourceGroup: false, createServer: false });
            }}>
            {matchingSubscriptions.map(item => <Option key={item.id} value={item.id} text={`${item.name} · ${item.id}`}><span className="subscription-result"><strong>{item.name}</strong><span>{item.id}</span></span></Option>)}
            {matchingSubscriptions.length === 0 && <Option disabled>No matching subscriptions</Option>}
          </Combobox>
          <span id="subscription-search-hint" className="field-hint">Search by name or ID, then select a matching subscription.</span>
          </div>
          <ReadFeedback {...subscriptions} retry={subscriptions.reload} empty={subscriptions.data?.length === 0 ? 'No subscriptions available in this tenant.' : undefined} /></div>
        <Field label="Target database name" hint="A new, empty free-offer database. No overwrite."><input value={c.targetDatabase} maxLength={128} placeholder="Enter a new database name" onChange={event => change({ targetDatabase: event.target.value })} /></Field>
        <div className="resource-field">
          <Switch label="Create new resource group" checked={c.createResourceGroup} disabled={!c.subscriptionId} onChange={(_, data) => change({
            createResourceGroup: data.checked, resourceGroup: '', serverName: '', region: '', createServer: data.checked,
          })} />
          {c.createResourceGroup
            ? <Field label="New resource group"><input value={c.resourceGroup} placeholder="Resource group name" onChange={event => change({ resourceGroup: event.target.value })} /></Field>
            : <><Field label="Existing resource group"><select disabled={!c.subscriptionId || groups.loading} value={c.resourceGroup} onChange={event => change({ resourceGroup: event.target.value, serverName: '', region: '' })}>
              <option value="">Select a resource group</option>{groups.data?.map(item => <option key={item.id} value={item.name}>{item.name} · {item.region}</option>)}</select></Field>
              <ReadFeedback {...groups} retry={groups.reload} empty={groups.data?.length === 0 ? 'No groups returned. Create a new group or check access.' : undefined} /></>}
        </div>
        <div className="resource-field">
          <Switch label="Create new logical server" checked={c.createServer} disabled={!c.resourceGroup || c.createResourceGroup} onChange={(_, data) => change({ createServer: data.checked, serverName: '', region: '' })} />
          {c.createServer
            ? <Field label="New logical server" hint="1–63 lowercase letters, digits or hyphens; start and end with a letter or digit. Availability checked by the backend."><input value={c.serverName} maxLength={63} placeholder="Globally unique server name" onChange={event => change({ serverName: event.target.value })} /></Field>
            : <><Field label="Existing logical server"><select disabled={!c.resourceGroup || servers.loading} value={c.serverName} onChange={event => {
              const server = servers.data?.find(item => item.name === event.target.value);
              change({ serverName: event.target.value, region: server?.region ?? '' });
            }}>
              <option value="">Select a server</option>{servers.data?.map(item => <option key={item.id} value={item.name}>{item.name} · {item.region}</option>)}</select></Field>
              <ReadFeedback {...servers} retry={servers.reload} empty={servers.data?.length === 0 ? 'No servers returned. Create a new server or check access.' : undefined} /></>}
        </div>
        {c.createServer ? <div><Field label="Region for new resources" hint={c.createResourceGroup ? 'The new resource group and logical server will use this region.' : 'The new logical server and database will use this region.'}><select disabled={!c.subscriptionId || locations.loading} value={c.region} onChange={event => change({ region: event.target.value })}>
          <option value="">Select a region</option>{locations.data?.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></Field>
          <ReadFeedback {...locations} retry={locations.reload} empty={locations.data?.length === 0 ? 'No regions returned for this subscription.' : undefined} /></div>
          : c.serverName && <p className="muted">Database region: <strong>{c.region}</strong> · inherited from the selected logical server.</p>}
      </div>
      <div className="identity-card">
        <div className="card-title"><Person24Regular /><h3>Microsoft Entra identity</h3></div>
        <Field label="Authentication"><select value="Entra" onChange={() => undefined}><option value="Entra">Entra · current user as administrator</option><option disabled>SQL authentication · not implemented</option></select></Field>
        <ReadFeedback {...identity} retry={() => { setIdentityConfirmed(false); identity.reload(); }} />
        {!azureContext && <p className="muted">Select a tenant and subscription to resolve the actual signed-in identity.</p>}
        {identity.data && <><dl className="facts"><dt>Signed-in user</dt><dd>{identity.data.name}</dd><dt>Principal</dt><dd>{identity.data.userPrincipalName}</dd><dt>Object ID</dt><dd className="mono">{identity.data.id}</dd></dl>
          <Checkbox checked={identityConfirmed} onChange={(_, data) => setIdentityConfirmed(data.checked === true)} label="I confirm this identity for migration administration in the selected tenant." /></>}
        <p className="muted">This is not the application runtime identity. An existing administrator must not be replaced without separate approval; the backend must block conflicts.</p>
      </div>
    </fieldset>
    {error && <Notice title="Review could not be created" danger>{error}</Notice>}
    <div className="stage-actions"><span className="muted">A review is not deployment approval.</span>
      <Button appearance="primary" icon={<ArrowRight24Regular />} iconPosition="after" disabled={!valid || pending} onClick={() => { if (identity.data) review(identity.data); }}>
        {pending ? 'Preparing exact review…' : 'Build migration review'}
      </Button></div>
  </>;
}

export type Capability = { name: string; state: 'ready' | 'blocked' | 'unknown'; detail: string };
export type Skill = { name: string; title: string; sourceUrl: string; revision: string; adaptation: string };
export type Status = {
  serviceDeskUrl: string;
  capabilities: Capability[];
  skills: Skill[];
  copilot: { authenticated: boolean; status: string; models: { id: string; name: string }[] };
};
export type Container = { name: string; image: string; endpoint: string; state: string };
export type DatabaseDiscovery = {
  endpoint: string;
  databases: { name: string; tableCount: number; caseCount?: number }[];
};
export type Tenant = { id: string; name: string };
export type Subscription = { id: string; name: string; tenantId: string };
export type Location = { id: string; name: string };
export type ResourceGroup = { id: string; name: string; region: string };
export type Server = { id: string; name: string; region: string; fullyQualifiedDomainName: string };
export type Identity = { id: string; name: string; userPrincipalName: string };
export type Configuration = {
  containerName: string;
  sourceDatabase: string;
  tenantId: string;
  subscriptionId: string;
  region: string;
  resourceGroup: string;
  createResourceGroup: boolean;
  serverName: string;
  createServer: boolean;
  targetDatabase: string;
  authentication: 'Entra';
};
export type Step = { id: string; title: string; state: string; message: string };
export type Plan = {
  id: string;
  fingerprint: string;
  configuration: Configuration;
  summary: string[];
  state: 'review';
  createdAt: string;
  steps: Step[];
};
export type Run = { id: string; state: string; steps: Step[]; validation?: Record<string, unknown>; error?: string };
export type ActivityEvent = { id: string; time: string; stage: string; state: string; message: string; runId?: string | null; subject?: string | null };
export type CopilotEvent = { kind: 'delta' | 'done' | 'error'; text: string };
export type CopilotSignIn = {
  id: string | null;
  message: string;
} & ({
  state: 'waiting';
  userCode: string;
  verificationUri: string;
  expiresAt: string;
} | {
  state: 'idle' | 'connected' | 'failed' | 'cancelled' | 'expired';
  userCode?: null;
  verificationUri?: null;
  expiresAt?: null;
});
export type ChatMessage = { id: number; role: 'user' | 'assistant'; text: string };

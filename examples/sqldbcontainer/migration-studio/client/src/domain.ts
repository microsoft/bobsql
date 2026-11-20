import type { ActivityEvent, ChatMessage, Configuration } from './types.ts';

export const confirmationPhrase = 'CREATE FREE DATABASE AND MIGRATE';
export const emptyConfiguration: Configuration = {
  containerName: '', sourceDatabase: '', tenantId: '', subscriptionId: '', region: '',
  resourceGroup: '', createResourceGroup: false, serverName: '', createServer: false,
  targetDatabase: '', authentication: 'Entra',
};
export function configurationKey(value: Configuration): string {
  return JSON.stringify([
    value.containerName, value.sourceDatabase, value.tenantId, value.subscriptionId,
    value.region, value.resourceGroup, value.createResourceGroup, value.serverName,
    value.createServer, value.targetDatabase, value.authentication,
  ]);
}
export function canExecute(phrase: string, writersStopped: boolean, current: Configuration, planned: Configuration): boolean {
  return writersStopped && phrase === confirmationPhrase && configurationKey(current) === configurationKey(planned);
}
export function appendActivity(events: ActivityEvent[], incoming: ActivityEvent): ActivityEvent[] {
  if (events.some(event => event.id === incoming.id)) return events;
  return [...events, incoming].slice(-500);
}
export function appendChatDelta(messages: ChatMessage[], id: number, text: string): ChatMessage[] {
  return messages.map(message => message.id === id ? { ...message, text: message.text + text } : message);
}
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
export function parseActivity(value: unknown): ActivityEvent {
  if (!isRecord(value) || !['time', 'stage', 'state', 'message'].every(key => typeof value[key] === 'string')
      || !(typeof value.id === 'string' || (typeof value.id === 'number' && Number.isSafeInteger(value.id)))
      || (value.runId != null && typeof value.runId !== 'string')
      || (value.subject != null && typeof value.subject !== 'string')) {
    throw new Error('The server sent an invalid activity event.');
  }
  return { ...value, id: String(value.id) } as ActivityEvent;
}
export function skillReadState(events: ActivityEvent[], name: string): string {
  const latest = events.slice().reverse().find(event => event.stage === 'skill' && event.subject === name && event.state !== 'available');
  return latest?.state === 'completed' ? 'read' : latest?.state === 'started' ? 'reading' : latest?.state === 'failed' ? 'failed' : 'not read';
}
export function copilotActivity(events: ActivityEvent[]): ActivityEvent[] {
  return events.filter(event => ['skill', 'tool', 'copilot'].includes(event.stage));
}
export function safeWebUrl(value: string): string | undefined {
  try {
    const url = new URL(value);
    return ['http:', 'https:'].includes(url.protocol) ? url.href : undefined;
  } catch {
    return undefined;
  }
}
export function isTerminal(state: string): boolean {
  return ['completed', 'succeeded', 'failed', 'cancelled', 'canceled', 'blocked'].includes(state.toLowerCase());
}

import { isRecord } from './domain.ts';

export class ApiError extends Error {
  readonly status: number;
  constructor(message: string, status: number) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}
let sessionRequest: Promise<string> | undefined;

async function decode<T>(response: Response): Promise<T> {
  const text = await response.text();
  let value: unknown;
  try { value = text ? JSON.parse(text) : undefined; } catch {
    throw new ApiError(`The local API returned an unreadable response (HTTP ${response.status}). Verify that the backend is running on this origin.`, response.status);
  }
  if (!response.ok) {
    const problem = isRecord(value) ? value : {};
    const title = typeof problem.title === 'string' ? problem.title : `Request failed (HTTP ${response.status})`;
    const detail = typeof problem.detail === 'string' ? problem.detail : 'Check local service readiness and authentication, then retry explicitly.';
    throw new ApiError(`${title}: ${detail}`, response.status);
  }
  if (value === undefined) throw new ApiError('The local API returned an empty response.', response.status);
  return value as T;
}
async function readRaw<T>(path: string, signal?: AbortSignal): Promise<T> {
  try {
    const response = await fetch(path, { credentials: 'same-origin', headers: { Accept: 'application/json' }, signal });
    if (response.status === 401 || response.status === 403) sessionRequest = undefined;
    return await decode<T>(response);
  } catch (error) {
    if (error instanceof ApiError || (error instanceof DOMException && error.name === 'AbortError')) throw error;
    throw new ApiError('Not connected to the local API. Check that the Migration Studio backend is running on this origin, then retry.', 0);
  }
}
export async function ensureSession(): Promise<string> {
  sessionRequest ??= readRaw<{ csrfToken: string }>('/api/session').then(session => {
    if (typeof session.csrfToken !== 'string' || !session.csrfToken) throw new ApiError('The local session did not supply a CSRF token. Reconnect before continuing.', 0);
    return session.csrfToken;
  }).catch(error => { sessionRequest = undefined; throw error; });
  return sessionRequest;
}
export async function get<T>(path: string, signal?: AbortSignal): Promise<T> {
  if (path !== '/api/session') await ensureSession();
  return readRaw<T>(path, signal);
}
export async function post<T>(path: string, body: unknown): Promise<T> {
  const token = await ensureSession();
  let response: Response;
  try {
    response = await fetch(path, {
      method: 'POST', credentials: 'same-origin',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'X-CSRF-TOKEN': token },
      body: JSON.stringify(body),
    });
  } catch {
    throw new ApiError('Connection lost. The request outcome is unknown. Inspect live activity and server state before retrying; no operation was automatically repeated.', 0);
  }
  if (response.status === 401 || response.status === 403) sessionRequest = undefined;
  // Accepted commands may intentionally have no response body.
  if (response.ok && (response.status === 202 || response.status === 204)) {
    const text = await response.text();
    if (!text) return undefined as T;
    try { return JSON.parse(text) as T; } catch {
      throw new ApiError('The command was accepted but returned an unreadable response. Inspect server state before repeating it.', response.status);
    }
  }
  return decode<T>(response);
}
export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'An unexpected error occurred. Inspect the local service and retry explicitly.';
}

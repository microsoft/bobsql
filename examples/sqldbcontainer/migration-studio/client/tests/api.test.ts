import assert from 'node:assert/strict';
import test from 'node:test';
import { get, post } from '../src/api.ts';

test('transport shows Problem Details, protects every POST, and never retries commands', async () => {
  const original = globalThis.fetch;
  const calls: { path: string; init?: RequestInit }[] = [];
  let mode = 'problem';
  globalThis.fetch = async (input: string | URL | Request, init?: RequestInit) => {
    const path = String(input);
    calls.push({ path, init });
    if (path === '/api/session') return Response.json({ csrfToken: 'test-session-token' });
    if (mode === 'problem') return Response.json({ title: 'Source blocked', detail: 'Source must already be READ_ONLY.' }, { status: 409 });
    if (mode === 'offline') throw new TypeError('network disconnected');
    if (mode === 'accepted') return new Response(null, { status: 202 });
    return Response.json({ id: 'real-backend-id' }, { status: 202 });
  };
  try {
    await assert.rejects(get('/api/status'), /Source blocked: Source must already be READ_ONLY/);
    assert.equal(calls[0].path, '/api/session', 'session bootstrap precedes API reads');
    assert.equal(calls[1].path, '/api/status');
    mode = 'success';
    const result = await post<{ id: string }>('/api/plans', { authentication: 'Entra' });
    assert.equal(result.id, 'real-backend-id');
    const command = calls.find(call => call.path === '/api/plans');
    assert.equal(command?.init?.method, 'POST');
    assert.equal(command?.init?.credentials, 'same-origin');
    assert.equal((command?.init?.headers as Record<string, string>)['X-CSRF-TOKEN'], 'test-session-token');
    assert.equal(calls.find(call => call.path === '/api/session')?.init?.credentials, 'same-origin');
    mode = 'accepted';
    assert.equal(await post('/api/copilot/message', { text: 'Readiness?' }), undefined);
    mode = 'offline';
    const before = calls.length;
    await assert.rejects(post('/api/plans/id/run', {}), /outcome is unknown/);
    assert.equal(calls.length, before + 1, 'a command must never auto-retry');
    await assert.rejects(get('/api/status'), /Not connected/);
  } finally { globalThis.fetch = original; }
});

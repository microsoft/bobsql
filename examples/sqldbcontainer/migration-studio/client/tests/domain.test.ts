import assert from 'node:assert/strict';
import test from 'node:test';
import { appendActivity, appendChatDelta, canExecute, configurationKey, confirmationPhrase, copilotActivity, emptyConfiguration, isTerminal, parseActivity, safeWebUrl, skillReadState } from '../src/domain.ts';
import type { ActivityEvent } from '../src/types.ts';

test('execution requires exact phrase and acknowledgment of all writers', () => {
  const c = { ...emptyConfiguration };
  assert.equal(canExecute(confirmationPhrase, true, c, c), true);
  assert.equal(canExecute(confirmationPhrase, false, c, c), false);
  assert.equal(canExecute(confirmationPhrase.toLowerCase(), true, c, c), false);
  assert.equal(canExecute(`${confirmationPhrase} `, true, c, c), false);
});
test('every configuration choice invalidates the prior approval', () => {
  for (const key of Object.keys(emptyConfiguration) as (keyof typeof emptyConfiguration)[]) {
    const changed = { ...emptyConfiguration, [key]: typeof emptyConfiguration[key] === 'boolean' ? true : 'changed' };
    assert.notEqual(configurationKey(changed), configurationKey(emptyConfiguration), key);
    assert.equal(canExecute(confirmationPhrase, true, changed, emptyConfiguration), false, key);
  }
});
test('harmless extra backend fields do not invalidate configuration equality', () => {
  assert.equal(configurationKey({ ...emptyConfiguration, ...{ extraMetadata: 'ignored' } }), configurationKey(emptyConfiguration));
});
test('activity journal retains newest 500 real events and deduplicates replayed IDs', () => {
  let events: ActivityEvent[] = [];
  for (let index = 0; index < 510; index++) events = appendActivity(events, { id: String(index), time: 'server-time', stage: 'export', state: 'running', message: String(index) });
  assert.equal(events.length, 500);
  assert.equal(events[0].id, '10');
  assert.equal(events.at(-1)?.id, '509');
  assert.equal(appendActivity(events, events[499]), events);
});
test('malformed live activity is rejected, not represented as a successful event', () => {
  assert.throws(() => parseActivity({ id: '1', state: 'completed' }), /invalid/);
  assert.throws(() => parseActivity({ id: '1', time: 'now', stage: 'import', state: 'running', message: 'test', runId: 1 }), /invalid/);
});
test('real SSE numeric IDs and null optional fields are accepted and replay deduplicated', () => {
  const event = parseActivity({ id: 12, time: '2026-11-17T17:00:00Z', stage: 'tool', state: 'completed', message: 'Returned.', runId: null, subject: 'inspect_readiness' });
  assert.equal(event.id, '12');
  assert.equal(appendActivity([event], parseActivity({ ...event, id: 12 })).length, 1);
  assert.throws(() => parseActivity({ ...event, subject: {} }), /invalid/);
});
test('skill badges distinguish availability, tool calls, actual reads and failures', () => {
  const event: ActivityEvent = { id: '1', time: 'now', stage: 'skill', state: 'available', message: 'Supplied.', subject: 'migration' };
  assert.equal(skillReadState([event], 'migration'), 'not read');
  assert.equal(skillReadState([{ ...event, stage: 'tool', state: 'completed' }], 'migration'), 'not read');
  assert.equal(skillReadState([{ ...event, state: 'completed', subject: 'other' }], 'migration'), 'not read');
  assert.equal(skillReadState([{ ...event, state: 'started' }], 'migration'), 'reading');
  assert.equal(skillReadState([{ ...event, state: 'completed' }], 'migration'), 'read');
  assert.equal(skillReadState([{ ...event, state: 'completed' }, { ...event, id: '2', state: 'failed' }], 'migration'), 'failed');
});
test('Copilot inspector excludes wizard and migration operations even when completed', () => {
  const stages = ['wizard', 'migration', 'review', 'approval', 'export', 'skill', 'tool', 'copilot'];
  const events = stages.map((stage, id) => ({ id: String(id), stage, time: 'now', state: 'completed', message: 'Test' }));
  assert.deepEqual(copilotActivity(events).map(event => event.stage), ['skill', 'tool', 'copilot']);
  assert.equal(events.length, stages.length);
});
test('server links accept only explicit http(s) URLs', () => {
  assert.equal(safeWebUrl('javascript:alert(1)'), undefined);
  assert.equal(safeWebUrl('data:text/html,hi'), undefined);
  assert.equal(safeWebUrl('https://learn.microsoft.com/'), 'https://learn.microsoft.com/');
  assert.equal(safeWebUrl('http://localhost:5187/'), 'http://localhost:5187/');
});
test('terminal runs stop polling without equating failed or blocked to success', () => {
  for (const state of ['completed', 'succeeded', 'failed', 'blocked', 'cancelled']) assert.equal(isTerminal(state), true);
  assert.equal(isTerminal('running'), false);
  assert.equal(isTerminal('unknown'), false);
});
test('streamed deltas append to the targeted message without losing earlier tokens', () => {
  const initial = [{ id: 1, role: 'user' as const, text: 'Readiness?' }, { id: 2, role: 'assistant' as const, text: '' }];
  const first = appendChatDelta(initial, 2, 'Source ');
  const second = appendChatDelta(first, 2, 'blocked.');
  assert.equal(second[1].text, 'Source blocked.');
  assert.equal(second[0].text, 'Readiness?');
  assert.equal(initial[1].text, '', 'React state updates remain immutable');
});

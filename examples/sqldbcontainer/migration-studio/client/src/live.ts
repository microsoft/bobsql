import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError, ensureSession, errorMessage, post } from './api.ts';
import { appendActivity, appendChatDelta, isRecord, parseActivity } from './domain.ts';
import type { ActivityEvent, ChatMessage, CopilotEvent } from './types.ts';

export function useLive() {
  const [revision, setRevision] = useState(0);
  const [connection, setConnection] = useState<'connecting' | 'connected' | 'disconnected'>('connecting');
  const [streamError, setStreamError] = useState('');
  const [events, setEvents] = useState<ActivityEvent[]>([]);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [sending, setSending] = useState(false);
  const [chatError, setChatError] = useState('');
  const pending = useRef(false);
  const assistantId = useRef<number | null>(null);
  const nextId = useRef(0);
  const hasDelta = useRef(false);
  useEffect(() => {
    setConnection('connecting');
    let disposed = false;
    let cleanup = () => {};
    function connect() {
    if (disposed) return;
    const stream = new EventSource('/api/events', { withCredentials: true });
    stream.onopen = () => { setConnection('connected'); setStreamError(''); };
    stream.onerror = () => {
      setConnection('disconnected');
      setStreamError('Live stream disconnected. Reconnecting automatically; missing activity is not proof of completion.');
      if (pending.current) setChatError('Copilot stream interrupted. This send remains locked until the server reports done or error. Reconnect to recover; do not resend.');
    };
    stream.onmessage = event => {
      try {
        const incoming = parseActivity(JSON.parse(event.data) as unknown);
        setEvents(previous => appendActivity(previous, incoming));
      } catch (error) { setStreamError(errorMessage(error)); }
    };
    const onCopilot = (event: MessageEvent<string>) => {
      try {
        const value: unknown = JSON.parse(event.data);
        if (!isRecord(value) || !['delta', 'done', 'error'].includes(String(value.kind)) || typeof value.text !== 'string') {
          throw new Error('The server sent an invalid Copilot event.');
        }
        const incoming = value as CopilotEvent;
        if (assistantId.current === null) {
          const id = ++nextId.current;
          assistantId.current = id;
          hasDelta.current = false;
          setMessages(previous => [...previous, { id, role: 'assistant', text: '' }]);
        }
        const id = assistantId.current;
        if (incoming.kind === 'delta') {
          hasDelta.current = true;
          setMessages(previous => appendChatDelta(previous, id, incoming.text));
        } else {
          if (incoming.kind === 'error') setChatError(incoming.text || 'The Copilot request failed. Check authentication and local logs.');
          if (!hasDelta.current && incoming.text) {
            setMessages(previous => previous.map(message => message.id === id ? { ...message, text: incoming.text } : message));
          }
          pending.current = false;
          assistantId.current = null;
          setSending(false);
        }
      } catch (error) { setChatError(errorMessage(error)); }
    };
    stream.addEventListener('copilot', onCopilot);
    cleanup = () => { stream.removeEventListener('copilot', onCopilot); stream.close(); };
    }
    void ensureSession().then(connect).catch(error => {
      if (!disposed) {
        setConnection('disconnected');
        setStreamError(`Local session could not be established: ${errorMessage(error)} Use Reconnect stream to retry.`);
      }
    });
    return () => { disposed = true; cleanup(); };
  }, [revision]);

  const send = useCallback(async (text: string, model?: string) => {
    if (pending.current || !text.trim()) return false;
    pending.current = true;
    hasDelta.current = false;
    setSending(true);
    setChatError('');
    const id = ++nextId.current;
    assistantId.current = id;
    setMessages(previous => [...previous.slice(-198), { id: ++nextId.current, role: 'user', text: text.trim() }, { id, role: 'assistant', text: '' }]);
    try {
      await post<unknown>('/api/copilot/message', { text: text.trim(), ...(model ? { model } : {}) });
      // Only a streamed done/error event ends a successfully accepted send.
    } catch (error) {
      const uncertain = error instanceof ApiError && (error.status === 0 || error.status >= 500 || (error.status >= 200 && error.status < 300));
      setChatError(`${errorMessage(error)}${uncertain ? ' Send locked because its outcome is unknown. Reconnect for the terminal event.' : ''}`);
      if (!uncertain) {
        pending.current = false;
        assistantId.current = null;
        setSending(false);
      }
    }
    return true;
  }, []);
  return { connection, streamError, events, messages, sending, chatError, send, reconnect: () => setRevision(value => value + 1) };
}
export type LiveState = ReturnType<typeof useLive>;

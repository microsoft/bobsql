import { useCallback, useEffect, useState } from 'react';
import { errorMessage, get } from './api.ts';

type ReadState<T> = { data?: T; loading: boolean; error?: string; reload: () => void };
export function useRead<T>(path: string | null): ReadState<T> {
  const [revision, setRevision] = useState(0);
  const [state, setState] = useState<{ path: string | null; data?: T; loading: boolean; error?: string }>({ path, loading: !!path });
  useEffect(() => {
    if (!path) {
      setState({ path, loading: false });
      return;
    }
    const controller = new AbortController();
    setState({ path, loading: true });
    void get<T>(path, controller.signal).then(data => {
      if (!controller.signal.aborted) setState({ path, loading: false, data });
    }).catch(error => {
      if (!controller.signal.aborted) setState({ path, loading: false, error: errorMessage(error) });
    });
    return () => controller.abort();
  }, [path, revision]);
  const reload = useCallback(() => setRevision(value => value + 1), []);
  // Never expose a previous tenant/subscription's data while effects are pending.
  return { ...(state.path === path ? state : { loading: !!path }), reload };
}

import { useEffect, useState } from 'react';
import { readJson } from './catalog.ts';
// Each section retains its last successful value while retrying.
export type PublishedSection<T> = {
  value?: T;
  loading: boolean;
  error: boolean;
  reload: () => void;
};

export function usePublished<T>(url: string): PublishedSection<T> {
  const [value, setValue] = useState<T>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError(false);
    void readJson<T>(url)
      .then(next => { if(alive) setValue(next); })
      .catch(() => { if(alive) setError(true); })
      .finally(() => { if(alive) setLoading(false); });
    return () => { alive = false; };
  }, [url, attempt]);
  return { value, loading, error, reload: () => setAttempt(previous => previous + 1) };
}

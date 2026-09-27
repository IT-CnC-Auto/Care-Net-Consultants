import { useEffect, useState } from 'react';

/** The current time, refreshed every few seconds, for countdowns such as the 10 minute step up. */
export function useNow(everyMs = 15000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), everyMs);
    return () => clearInterval(t);
  }, [everyMs]);
  return now;
}

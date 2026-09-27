// Passes a scanned code from the scan screen back to the screen that opened it.

type Listener = (data: string) => void;
const listeners = new Set<Listener>();

export function onScan(l: Listener): () => void {
  listeners.add(l);
  return () => {
    listeners.delete(l);
  };
}

export function emitScan(data: string): void {
  for (const l of Array.from(listeners)) l(data);
}

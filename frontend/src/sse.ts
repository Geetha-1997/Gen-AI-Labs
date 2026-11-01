export type StreamEvent = { token?: string; error?: string; done?: boolean };

/** Parse one complete Server-Sent Event block. Returns null for comments or malformed data. */
export function parseSseEvent(event: string): StreamEvent | null {
  const dataLine = event.split(/\r?\n/).find((line) => line.startsWith('data: '));
  if (!dataLine) return null;

  try {
    return JSON.parse(dataLine.slice(6)) as StreamEvent;
  } catch {
    return null;
  }
}

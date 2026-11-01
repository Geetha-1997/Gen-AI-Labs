import { describe, expect, it } from 'vitest';
import { parseSseEvent } from './sse';

describe('parseSseEvent', () => {
  it('parses streamed token data', () => {
    expect(parseSseEvent('data: {"token":"Hello"}')).toEqual({ token: 'Hello' });
  });

  it('parses completion events', () => {
    expect(parseSseEvent('data: {"done":true}')).toEqual({ done: true });
  });

  it('returns provider errors', () => {
    expect(parseSseEvent('data: {"error":"Unavailable"}')).toEqual({ error: 'Unavailable' });
  });

  it('ignores comments and malformed events', () => {
    expect(parseSseEvent(': keep-alive')).toBeNull();
    expect(parseSseEvent('data: not-json')).toBeNull();
  });
});

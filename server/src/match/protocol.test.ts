import { describe, expect, it } from 'vitest';
import { clampStepSeconds, DEFAULT_PARAMS, parseAction } from './protocol';

describe('parseAction', () => {
  it('accepts the four action shapes', () => {
    expect(parseAction({ type: 'take_supply' })).toEqual({ type: 'take_supply' });
    expect(parseAction({ type: 'take_market', cardId: 3 })).toEqual({ type: 'take_market', cardId: 3 });
    expect(parseAction({ type: 'play_portfolio', cardId: 0 })).toEqual({ type: 'play_portfolio', cardId: 0 });
    expect(parseAction({ type: 'play_market', cardId: 44, extra: 'ignored' })).toEqual({ type: 'play_market', cardId: 44 });
  });

  it('rejects payloads that would make the engine throw', () => {
    for (const bad of [null, undefined, 'take_supply', 7, [], {}, { type: 'steal' }, { type: 'take_market' }, { type: 'play_market', cardId: '3' }, { type: 'play_portfolio', cardId: 1.5 }, { type: 'take_market', cardId: null }]) {
      expect(parseAction(bad)).toBeNull();
    }
  });
});

describe('clampStepSeconds', () => {
  it('keeps the timer off or within the allowed range', () => {
    expect(clampStepSeconds(undefined)).toBe(DEFAULT_PARAMS.stepSeconds);
    expect(clampStepSeconds('abc')).toBe(DEFAULT_PARAMS.stepSeconds);
    expect(clampStepSeconds(0)).toBe(0);
    expect(clampStepSeconds(1)).toBe(5);
    expect(clampStepSeconds(30)).toBe(30);
    expect(clampStepSeconds(10000)).toBe(120);
  });
});

import { describe, expect, it } from 'vitest';
import { clampStepSeconds, DEFAULT_PARAMS } from './protocol';

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

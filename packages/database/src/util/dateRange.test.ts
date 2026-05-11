import { describe, expect, it } from 'vitest';
import { rangeFor, resolveDateRange } from './dateRange.js';

const NOW = new Date('2026-05-13T10:00:00Z'); // Wednesday

describe('rangeFor', () => {
  it('today', () => {
    expect(rangeFor('today', NOW)).toEqual({ start: '2026-05-13', end: '2026-05-13' });
  });

  it('yesterday', () => {
    expect(rangeFor('yesterday', NOW)).toEqual({ start: '2026-05-12', end: '2026-05-12' });
  });

  it('this_week (ISO Monday-start)', () => {
    // 2026-05-13 is Wed → week starts Mon 2026-05-11, ends Sun 2026-05-17.
    expect(rangeFor('this_week', NOW)).toEqual({ start: '2026-05-11', end: '2026-05-17' });
  });

  it('last_week', () => {
    expect(rangeFor('last_week', NOW)).toEqual({ start: '2026-05-04', end: '2026-05-10' });
  });

  it('this_month', () => {
    expect(rangeFor('this_month', NOW)).toEqual({ start: '2026-05-01', end: '2026-05-31' });
  });

  it('last_month', () => {
    expect(rangeFor('last_month', NOW)).toEqual({ start: '2026-04-01', end: '2026-04-30' });
  });

  it('this_year', () => {
    expect(rangeFor('this_year', NOW)).toEqual({ start: '2026-01-01', end: '2026-12-31' });
  });

  it('all_time spans full DATE domain', () => {
    expect(rangeFor('all_time', NOW)).toEqual({ start: '0001-01-01', end: '9999-12-31' });
  });

  it('week containing year boundary stays consistent', () => {
    // Fri 2027-01-01 → ISO week Mon 2026-12-28.
    const newYear = new Date('2027-01-01T10:00:00Z');
    expect(rangeFor('this_week', newYear)).toEqual({ start: '2026-12-28', end: '2027-01-03' });
  });
});

describe('resolveDateRange', () => {
  it('explicit startDate+endDate wins over dateRange', () => {
    expect(
      resolveDateRange({ startDate: '2026-01-01', endDate: '2026-01-31', dateRange: 'today' }),
    ).toEqual({ start: '2026-01-01', end: '2026-01-31' });
  });

  it('returns null when no filter given', () => {
    expect(resolveDateRange({})).toBeNull();
  });

  it('lone startDate without endDate is null (range only resolves when paired)', () => {
    expect(resolveDateRange({ startDate: '2026-01-01' })).toBeNull();
  });
});

import { describe, expect, it } from 'vitest';
import { buildChartConfig, defaultGranularity } from './chartSpending.js';

describe('defaultGranularity', () => {
  it('picks day for short ranges', () => {
    expect(defaultGranularity('2026-05-01', '2026-05-07')).toBe('day');
  });
  it('picks week for ~1 month', () => {
    expect(defaultGranularity('2026-04-01', '2026-04-30')).toBe('week');
  });
  it('picks month for half-year', () => {
    expect(defaultGranularity('2026-01-01', '2026-06-30')).toBe('month');
  });
});

describe('buildChartConfig', () => {
  const totalsByCategory = [
    { category: 'Groceries', total: 15 },
    { category: 'Pets', total: 10 },
  ];
  const buckets = ['2026-04-06', '2026-04-13'];
  const categories = ['Groceries', 'Pets'];
  const matrix = [
    [8, 0],
    [7, 10],
  ];

  it('emits bar dataset per category with stacked scales', () => {
    const cfg = buildChartConfig({
      buckets,
      categories,
      matrix,
      totalsByCategory,
      chartType: 'bar',
      currency: 'GBP',
      stacked: true,
    }) as {
      type: string;
      data: { labels: string[]; datasets: { label: string; data: number[] }[] };
      options: { scales: { x: { stacked: boolean }; y: { stacked: boolean } } };
    };
    expect(cfg.type).toBe('bar');
    expect(cfg.data.labels).toEqual(buckets);
    expect(cfg.data.datasets.map((d) => d.label)).toEqual(['Groceries', 'Pets']);
    expect(cfg.data.datasets[0].data).toEqual([8, 7]);
    expect(cfg.data.datasets[1].data).toEqual([0, 10]);
    expect(cfg.options.scales.x.stacked).toBe(true);
    expect(cfg.options.scales.y.stacked).toBe(true);
  });

  it('flips bar to non-stacked when stacked=false', () => {
    const cfg = buildChartConfig({
      buckets,
      categories,
      matrix,
      totalsByCategory,
      chartType: 'bar',
      currency: 'GBP',
      stacked: false,
    }) as { options: { scales: { x: { stacked: boolean } } } };
    expect(cfg.options.scales.x.stacked).toBe(false);
  });

  it('emits a doughnut from totals only', () => {
    const cfg = buildChartConfig({
      buckets,
      categories,
      matrix,
      totalsByCategory,
      chartType: 'doughnut',
      currency: 'GBP',
      stacked: false,
    }) as {
      type: string;
      data: { labels: string[]; datasets: { data: number[] }[] };
    };
    expect(cfg.type).toBe('doughnut');
    expect(cfg.data.labels).toEqual(['Groceries', 'Pets']);
    expect(cfg.data.datasets[0].data).toEqual([15, 10]);
  });
});

import { createTool } from '@mastra/core/tools';
import { expensesRepo } from '@mr-carson/database';
import {
  ChartSpendingArgsSchema,
  ChartSpendingResultSchema,
  type ChartType,
  type Granularity,
} from '@mr-carson/shared-types';

export interface ChartSink {
  imageBase64?: string;
}

const QUICKCHART_URL = process.env.QUICKCHART_URL ?? 'https://quickchart.io/chart';

const PALETTE = [
  '#2563eb',
  '#16a34a',
  '#dc2626',
  '#f59e0b',
  '#7c3aed',
  '#0891b2',
  '#db2777',
  '#65a30d',
  '#ea580c',
  '#4b5563',
];

function pickChartType(
  requested: ChartType | undefined,
  bucketCount: number,
  categoryCount: number,
): ChartType {
  if (requested) return requested;
  if (bucketCount <= 1) return categoryCount <= 8 ? 'doughnut' : 'bar';
  return 'bar';
}

function defaultGranularity(start: string, end: string): Granularity {
  const days = (Date.parse(end) - Date.parse(start)) / 86_400_000;
  if (days <= 14) return 'day';
  if (days <= 120) return 'week';
  return 'month';
}

interface RenderInput {
  buckets: string[];
  categories: string[];
  matrix: number[][]; // matrix[bucketIdx][categoryIdx]
  totalsByCategory: { category: string; total: number }[];
  chartType: ChartType;
  currency: string;
  stacked: boolean;
}

function buildChartConfig(input: RenderInput): object {
  const { buckets, categories, matrix, totalsByCategory, chartType, currency, stacked } = input;

  if (chartType === 'pie' || chartType === 'doughnut') {
    return {
      type: chartType,
      data: {
        labels: totalsByCategory.map((c) => c.category),
        datasets: [
          {
            data: totalsByCategory.map((c) => Math.round(c.total * 100) / 100),
            backgroundColor: totalsByCategory.map((_, i) => PALETTE[i % PALETTE.length]),
          },
        ],
      },
      options: {
        plugins: {
          title: { display: true, text: `Spending by category (${currency})` },
          legend: { position: 'right' },
        },
      },
    };
  }

  const datasets = categories.map((cat, ci) => ({
    label: cat,
    data: buckets.map((_, bi) => Math.round((matrix[bi]?.[ci] ?? 0) * 100) / 100),
    backgroundColor: PALETTE[ci % PALETTE.length],
    borderColor: PALETTE[ci % PALETTE.length],
    fill: chartType === 'line' ? false : undefined,
  }));

  return {
    type: chartType,
    data: { labels: buckets, datasets },
    options: {
      plugins: {
        title: { display: true, text: `Spending trend (${currency})` },
        legend: { position: 'bottom' },
      },
      scales: {
        x: { stacked: chartType === 'bar' && stacked },
        y: { stacked: chartType === 'bar' && stacked, beginAtZero: true },
      },
    },
  };
}

async function renderViaQuickChart(config: object): Promise<string> {
  const res = await fetch(QUICKCHART_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      chart: config,
      width: 800,
      height: 480,
      backgroundColor: 'white',
      format: 'png',
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`QuickChart ${res.status}: ${body.slice(0, 200)}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  return buf.toString('base64');
}

export const chartSpendingTool = createTool({
  id: 'chartSpending',
  description:
    'Render a chart of the user\'s spending over a date range, grouped by category. ' +
    'Use this whenever the user asks to "show", "chart", "graph", "visualize", or see a "trend" / "breakdown" of spending. ' +
    'Returns a summary; the chart image is delivered separately to the user.',
  inputSchema: ChartSpendingArgsSchema,
  outputSchema: ChartSpendingResultSchema,
  execute: async (inputData, { requestContext }) => {
    const userId = requestContext?.get('userId') as string;
    const sink = requestContext?.get('sink') as ChartSink | undefined;

    const { rows, granularity, currency } = await expensesRepo.byCategoryOverTime(userId, {
      dateRange: inputData.dateRange,
      startDate: inputData.startDate,
      endDate: inputData.endDate,
      category: inputData.category,
      granularity: inputData.granularity,
    });

    const buckets = Array.from(new Set(rows.map((r) => r.bucket))).sort();
    const categories = Array.from(new Set(rows.map((r) => r.category))).sort();
    const matrix: number[][] = buckets.map(() => categories.map(() => 0));
    const bucketIdx = new Map(buckets.map((b, i) => [b, i]));
    const catIdx = new Map(categories.map((c, i) => [c, i]));
    for (const r of rows) {
      const bi = bucketIdx.get(r.bucket)!;
      const ci = catIdx.get(r.category)!;
      matrix[bi]![ci] = r.total;
    }

    const totalsByCategory = categories
      .map((cat) => ({
        category: cat,
        total: Math.round(
          matrix.reduce((acc, row) => acc + (row[catIdx.get(cat)!] ?? 0), 0) * 100,
        ) / 100,
      }))
      .sort((a, b) => b.total - a.total);

    const grandTotal = totalsByCategory.reduce((a, b) => a + b.total, 0);
    const chartType = pickChartType(inputData.chartType, buckets.length, categories.length);
    const stacked = inputData.stacked ?? true;

    const summary =
      grandTotal === 0
        ? 'No spending found in that range.'
        : `Spent ${currency} ${grandTotal.toFixed(2)} across ${categories.length} categories over ${buckets.length} ${granularity}(s). Top: ${totalsByCategory
            .slice(0, 3)
            .map((c) => `${c.category} ${currency} ${c.total.toFixed(2)}`)
            .join(', ')}.`;

    if (grandTotal === 0) {
      return { summary, chartType, granularity, currency, totalsByCategory, buckets, imageBase64: '' };
    }

    const config = buildChartConfig({ buckets, categories, matrix, totalsByCategory, chartType, currency, stacked });
    const imageBase64 = await renderViaQuickChart(config);
    if (sink) sink.imageBase64 = imageBase64;

    return { summary, chartType, granularity, currency, totalsByCategory, buckets, imageBase64 };
  },
});

export { defaultGranularity, buildChartConfig };

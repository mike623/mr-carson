import { createTool } from '@mastra/core/tools';
import { z } from 'zod';
import { OcrResultSchema } from '@mr-carson/shared-types';

/**
 * Calls the GLM-OCR Python sidecar. The sidecar returns either:
 *   { structured: Expense, rawText, confidence } - structured extraction succeeded
 *   { structured: null,    rawText, confidence } - fallback: raw text only
 */
export const ocrTool = createTool({
  id: 'ocr',
  description:
    'Run GLM-OCR on a receipt file (image or PDF) and return structured JSON when possible, raw text as fallback.',
  inputSchema: z.object({
    filePath: z.string().describe('Absolute path to the receipt file on the local filesystem.'),
  }),
  outputSchema: OcrResultSchema,
  execute: async ({ context }) => {
    const url = (process.env.OCR_SERVICE_URL ?? 'http://localhost:8001') + '/ocr';
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ file_path: context.filePath }),
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`ocr sidecar ${res.status}: ${text}`);
    }
    const json = await res.json();
    return OcrResultSchema.parse(json);
  },
});

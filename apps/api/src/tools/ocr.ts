import { readFileSync } from 'node:fs';
import { createTool } from '@mastra/core/tools';
import { generateText } from 'ai';
import { z } from 'zod';
import { OcrResultSchema } from '@mr-carson/shared-types';
import { getOllamaProvider } from '../llm.js';

/**
 * Calls Ollama's `glm-ocr` model directly. GLM-OCR is a 0.9B vision model from
 * Z.ai specialized for document OCR — it accepts an image plus one of three
 * prompt prefixes: "Text Recognition:", "Formula Recognition:", "Table
 * Recognition:". We use Text Recognition for receipts and hand the result to
 * `extractReceipt` for structured-JSON conversion.
 *
 * Image-only by design: PDFs are rejected at the bot edge so we never need a
 * rasterizer here.
 */
export const ocrTool = createTool({
  id: 'ocr',
  description:
    'Run OCR on a receipt image via Ollama glm-ocr and return the recognized text. Structured extraction is done as a follow-up step.',
  inputSchema: z.object({
    filePath: z.string().describe('Absolute path to the receipt image on disk.'),
  }),
  outputSchema: OcrResultSchema,
  execute: async ({ context }) => {
    const modelId = process.env.OLLAMA_OCR_MODEL ?? 'glm-ocr';
    const model = getOllamaProvider().chatModel(modelId);
    const image = readFileSync(context.filePath);

    const { text } = await generateText({
      model,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', image },
            { type: 'text', text: 'Text Recognition:' },
          ],
        },
      ],
    });

    return {
      structured: null,
      rawText: text,
    };
  },
});

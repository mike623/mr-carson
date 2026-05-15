import { readFileSync } from 'node:fs';
import { createTool } from '@mastra/core/tools';
import { generateText } from 'ai';
import { z } from 'zod';
import { OcrResultSchema } from '@mr-carson/shared-types';
import { getOcrModel } from '../llm.js';

export const ocrTool = createTool({
  id: 'ocr',
  description:
    'Run OCR on a receipt image and return the recognized text. Structured extraction is done as a follow-up step.',
  inputSchema: z.object({
    filePath: z.string().describe('Absolute path to the receipt image on disk.'),
  }),
  outputSchema: OcrResultSchema,
  execute: async (inputData) => {
    const model = getOcrModel();
    const image = readFileSync(inputData.filePath);

    const { text } = await generateText({
      model,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', image },
            { type: 'text', text: 'Extract all text from this receipt image.' },
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

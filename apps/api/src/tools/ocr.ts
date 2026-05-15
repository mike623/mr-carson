import { readFileSync } from 'node:fs';
import { createTool } from '@mastra/core/tools';
import { generateText } from 'ai';
import { z } from 'zod';
import { OcrResultSchema } from '@mr-carson/shared-types';
import { getOllamaProvider } from '../llm.js';

/**
 * Calls the configured Ollama vision model for receipt OCR. Defaults to
 * PaddleOCR-VL:0.9b (936MB, 128K ctx, SOTA doc parsing) but can be swapped
 * via OLLAMA_OCR_MODEL. Image-only by design: PDFs are rejected at the bot
 * edge so we never need a rasterizer here.
 */
export const ocrTool = createTool({
  id: 'ocr',
  description:
    'Run OCR on a receipt image via an Ollama vision model and return the recognized text. Structured extraction is done as a follow-up step.',
  inputSchema: z.object({
    filePath: z.string().describe('Absolute path to the receipt image on disk.'),
  }),
  outputSchema: OcrResultSchema,
  execute: async (inputData) => {
    const modelId = process.env.OLLAMA_OCR_MODEL ?? 'MedAIBase/PaddleOCR-VL:0.9b';
    const model = getOllamaProvider().chatModel(modelId);
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

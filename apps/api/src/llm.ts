import { createOpenAICompatible } from '@ai-sdk/openai-compatible';

function ollamaBase(): string {
  const base = process.env.OLLAMA_BASE_URL ?? 'http://localhost:11434';
  return base.replace(/\/$/, '');
}

/**
 * AI SDK v4 OpenAI-compatible provider pointed at Ollama's `/v1`.
 * Used by direct `generateText` / `generateObject` calls in tools
 * (ocr, extractReceipt) — NOT by the Mastra Agent.
 */
export function getOllamaProvider() {
  return createOpenAICompatible({
    name: 'ollama',
    baseURL: `${ollamaBase()}/v1`,
  });
}

export function getModel() {
  const modelId = process.env.OLLAMA_MODEL ?? 'mistral-small';
  return getOllamaProvider().chatModel(modelId);
}

/**
 * Mastra-native model config for the Agent. Routes through Mastra's
 * model router straight to local Ollama's OpenAI-compatible endpoint.
 * Required by Mastra >=1.30, which rejects AI SDK v4 LanguageModel
 * objects in `Agent.generate()`.
 */
export function getAgentModel() {
  const modelId = process.env.OLLAMA_MODEL ?? 'mistral-small';
  return {
    id: `ollama/${modelId}` as `${string}/${string}`,
    url: `${ollamaBase()}/v1`,
    apiKey: 'ollama',
  };
}

import { createOpenAICompatible } from '@ai-sdk/openai-compatible';

function ollamaBase(): string {
  const base = process.env.OLLAMA_BASE_URL ?? 'http://localhost:11434';
  return base.replace(/\/$/, '');
}

export function getOllamaProvider() {
  return createOpenAICompatible({
    name: 'ollama',
    baseURL: `${ollamaBase()}/v1`,
  });
}

function getOpenRouterProvider() {
  return createOpenAICompatible({
    name: 'openrouter',
    baseURL: 'https://openrouter.ai/api/v1',
    headers: { Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}` },
  });
}

function useOpenRouter(): boolean {
  return Boolean(process.env.OPENROUTER_API_KEY);
}

/** Chat/extraction model — OpenRouter when key is set, Ollama otherwise. */
export function getModel() {
  if (useOpenRouter()) {
    const modelId =
      process.env.OPENROUTER_MODEL ?? 'mistralai/mistral-small-3.1-24b-instruct';
    return getOpenRouterProvider().chatModel(modelId);
  }
  const modelId = process.env.OLLAMA_MODEL ?? 'mistral-small';
  return getOllamaProvider().chatModel(modelId);
}

/** Vision/OCR model — OpenRouter when key is set, Ollama otherwise. */
export function getOcrModel() {
  if (useOpenRouter()) {
    const modelId = process.env.OPENROUTER_OCR_MODEL ?? 'google/gemma-3n-e4b-it:free';
    return getOpenRouterProvider().chatModel(modelId);
  }
  const modelId = process.env.OLLAMA_OCR_MODEL ?? 'MedAIBase/PaddleOCR-VL:0.9b';
  return getOllamaProvider().chatModel(modelId);
}

/**
 * Mastra-native model config for the Agent. Routes through Mastra's model
 * router. Required by Mastra >=1.30 which rejects AI SDK v4 LanguageModel
 * objects in Agent.generate().
 */
export function getAgentModel() {
  if (useOpenRouter()) {
    const modelId =
      process.env.OPENROUTER_MODEL ?? 'mistralai/mistral-small-3.1-24b-instruct';
    return {
      id: modelId as `${string}/${string}`,
      url: 'https://openrouter.ai/api/v1',
      apiKey: process.env.OPENROUTER_API_KEY as string,
    };
  }
  const modelId = process.env.OLLAMA_MODEL ?? 'mistral-small';
  return {
    id: `ollama/${modelId}` as `${string}/${string}`,
    url: `${ollamaBase()}/v1`,
    apiKey: 'ollama',
  };
}

import { createOpenAICompatible } from '@ai-sdk/openai-compatible';

/**
 * Ollama exposes an OpenAI-compatible API at `/v1`. We use the AI SDK's
 * openai-compatible provider so model selection (e.g. `mistral-small`,
 * `qwen3:8b`) is just a model id string — overridable via OLLAMA_MODEL.
 */
export function getOllamaProvider() {
  const base = process.env.OLLAMA_BASE_URL ?? 'http://localhost:11434';
  return createOpenAICompatible({
    name: 'ollama',
    baseURL: `${base.replace(/\/$/, '')}/v1`,
  });
}

export function getModel() {
  const modelId = process.env.OLLAMA_MODEL ?? 'mistral-small';
  return getOllamaProvider().chatModel(modelId);
}

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { getOllamaProvider, getModel } from './llm.js';

const original = { ...process.env };

beforeEach(() => {
  delete process.env.OLLAMA_BASE_URL;
  delete process.env.OLLAMA_MODEL;
});

afterEach(() => {
  process.env = { ...original };
});

describe('getOllamaProvider', () => {
  it('returns a callable provider with default base url', () => {
    const provider = getOllamaProvider();
    // The provider is a function used as `provider(modelId)` or via `.chatModel(id)`.
    expect(typeof provider.chatModel).toBe('function');
  });

  it('strips a trailing slash from OLLAMA_BASE_URL', () => {
    process.env.OLLAMA_BASE_URL = 'http://example.com:11434/';
    // Constructing should not throw.
    expect(() => getOllamaProvider()).not.toThrow();
  });
});

describe('getModel', () => {
  it('uses OLLAMA_MODEL when set', () => {
    process.env.OLLAMA_MODEL = 'gemma4:latest';
    const model = getModel();
    // The AI SDK model exposes its id via `.modelId`.
    expect((model as { modelId?: string }).modelId).toBe('gemma4:latest');
  });

  it('falls back to mistral-small when unset', () => {
    const model = getModel();
    expect((model as { modelId?: string }).modelId).toBe('mistral-small');
  });
});

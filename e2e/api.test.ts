const BASE = process.env.API_BASE_URL ?? 'http://localhost:47821';

describe('API e2e', () => {
  test('GET /health returns ok', async () => {
    const res = await fetch(`${BASE}/health`);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(typeof body.model).toBe('string');
    expect(typeof body.ocrModel).toBe('string');
  });

  test('GET /model returns provider info', async () => {
    const res = await fetch(`${BASE}/model`);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(typeof body.provider).toBe('string');
    expect(typeof body.agentModel).toBe('string');
    expect(typeof body.ocrModel).toBe('string');
  });

  test('POST /agent/new creates a thread', async () => {
    const res = await fetch(`${BASE}/agent/new`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ userId: 'e2e-test' }),
    });
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(typeof body.threadId).toBe('string');
    expect((body.threadId as string).length).toBeGreaterThan(0);
  });
});

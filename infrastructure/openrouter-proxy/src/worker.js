// Thin auth proxy: forwards OpenAI-compatible chat-completions requests to
// OpenRouter, injecting the API key server-side so it never ships in the app.
const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
    if (req.method !== 'POST') return cors(new Response('method not allowed', { status: 405 }));
    if (!new URL(req.url).pathname.endsWith('/v1/chat/completions')) {
      return cors(new Response('not found', { status: 404 }));
    }
    if (!env.OPENROUTER_API_KEY) return cors(new Response('proxy not configured', { status: 500 }));

    const body = await req.text();
    const upstream = await fetch(OPENROUTER_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.OPENROUTER_API_KEY}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://mr-carson.app',
        'X-Title': 'Mr. Carson',
      },
      body,
    });
    // Pass status + body straight through (streaming bodies pass through too).
    return cors(new Response(upstream.body, {
      status: upstream.status,
      headers: { 'Content-Type': upstream.headers.get('Content-Type') || 'application/json' },
    }));
  },
};

function cors(resp) {
  resp.headers.set('Access-Control-Allow-Origin', '*');
  resp.headers.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  resp.headers.set('Access-Control-Allow-Headers', 'Content-Type');
  return resp;
}

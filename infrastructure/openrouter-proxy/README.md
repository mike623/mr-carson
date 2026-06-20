# OpenRouter proxy (Cloudflare Worker)

Thin auth proxy so the app never holds the OpenRouter API key.
App → this Worker → OpenRouter. Forwards `POST /v1/chat/completions` verbatim.

## One-time setup
1. `npm i -g wrangler` (or `npx wrangler`)
2. `cd infrastructure/openrouter-proxy`
3. `wrangler secret put OPENROUTER_API_KEY`   # paste your OpenRouter key
4. `wrangler deploy`                        # prints the public URL

## Local dev (for simulator testing)
- `wrangler dev`  → serves at http://localhost:8787
- Provide the key locally with a `.dev.vars` file (gitignored):
  `echo 'OPENROUTER_API_KEY=sk-or-...' > .dev.vars`

## Smoke test
```bash
curl -s http://localhost:8787/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"google/gemini-2.0-flash-001","messages":[{"role":"user","content":"say ok"}]}' \
  | head -c 300
```
Expect a JSON body containing `"choices"`.

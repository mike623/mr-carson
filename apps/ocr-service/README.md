# OCR Sidecar — GLM-OCR

A small FastAPI service that wraps
[`zai-org/GLM-OCR`](https://huggingface.co/zai-org/GLM-OCR) and exposes:

- `GET /health` — liveness, reports whether weights are loaded.
- `POST /ocr` — `{ file_path }` → `{ structured?, rawText, confidence }`.

The Node API talks to this over plain HTTP (`OCR_SERVICE_URL`). Both processes
must see the same uploads directory; in Docker that's the shared `uploads`
volume mounted at `/data/uploads`.

## Run locally (without Docker)

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8001
```

The first request downloads the model from Hugging Face (~several GB).

"""GLM-OCR sidecar.

Wraps zai-org/GLM-OCR (https://huggingface.co/zai-org/GLM-OCR) behind a small
FastAPI surface. The Node side calls POST /ocr with a local file path and gets
back either a structured Expense JSON or raw text.

Why a sidecar: GLM-OCR is a Hugging Face transformers model and has no
first-class Node binding. Keeping it as a separate Python service also lets us
swap it out for a different OCR engine without touching the bot or API.
"""

from __future__ import annotations

import io
import json
import logging
import os
import re
from pathlib import Path
from typing import Optional

import pypdfium2 as pdfium
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel, Field

logger = logging.getLogger("ocr")
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO").upper())

MODEL_NAME = os.environ.get("OCR_MODEL", "zai-org/GLM-OCR")
DEFAULT_CURRENCY = os.environ.get("DEFAULT_CURRENCY", "GBP")

app = FastAPI(title="mr-carson-ocr", version="0.1.0")

_model = None
_processor = None


def _load_model() -> None:
    """Lazy-load the GLM-OCR model on first /ocr call.

    We avoid loading at import time so the container can boot and pass health
    checks before the (multi-GB) weights are downloaded.
    """
    global _model, _processor
    if _model is not None:
        return
    logger.info("loading %s ...", MODEL_NAME)
    from transformers import AutoModelForCausalLM, AutoProcessor  # noqa: WPS433

    _processor = AutoProcessor.from_pretrained(MODEL_NAME, trust_remote_code=True)
    _model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        trust_remote_code=True,
        torch_dtype="auto",
        device_map="auto",
    )
    logger.info("model loaded")


class OcrRequest(BaseModel):
    file_path: str = Field(..., description="Absolute path to a local image or PDF.")


class ExpenseItem(BaseModel):
    name: str
    amount: float
    category: str = "Other"


class Expense(BaseModel):
    merchant: str
    date: str
    currency: str
    total: float
    items: list[ExpenseItem]


class OcrResponse(BaseModel):
    structured: Optional[Expense] = None
    rawText: str = ""
    confidence: Optional[float] = None


@app.get("/health")
def health() -> dict:
    return {"ok": True, "model": MODEL_NAME, "loaded": _model is not None}


def _load_images(path: Path) -> list[Image.Image]:
    if path.suffix.lower() == ".pdf":
        doc = pdfium.PdfDocument(str(path))
        # Cap at 10 pages — receipts are rarely longer; protects against bombs.
        pages = [doc.get_page(i).render(scale=2).to_pil() for i in range(min(len(doc), 10))]
        return pages
    return [Image.open(path).convert("RGB")]


def _prompt() -> str:
    return (
        "You are extracting line items from a retail receipt. "
        "Return JSON with keys: merchant (string), date (YYYY-MM-DD), "
        "currency (3-letter ISO, default "
        f"{DEFAULT_CURRENCY}), total (number), items (array of "
        "{name, amount, category}). Skip subtotal/tax/duplicate-total rows. "
        "If a field is unknown, omit it from JSON. Output JSON only."
    )


def _run_model(images: list[Image.Image]) -> str:
    _load_model()
    assert _model is not None and _processor is not None
    # GLM-OCR's documented call shape may vary by revision; we keep this in one
    # place so we can adjust without disturbing the FastAPI surface.
    inputs = _processor(images=images, text=_prompt(), return_tensors="pt").to(_model.device)
    outputs = _model.generate(**inputs, max_new_tokens=1024)
    text = _processor.batch_decode(outputs, skip_special_tokens=True)[0]
    return text


_JSON_FENCE = re.compile(r"```(?:json)?\s*(.*?)\s*```", re.DOTALL)


def _try_extract_json(blob: str) -> Optional[dict]:
    """Pull the first JSON object out of the model's output, tolerating fences."""
    fenced = _JSON_FENCE.search(blob)
    candidate = fenced.group(1) if fenced else blob
    start = candidate.find("{")
    end = candidate.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        return json.loads(candidate[start : end + 1])
    except json.JSONDecodeError:
        return None


@app.post("/ocr", response_model=OcrResponse)
def ocr(req: OcrRequest) -> OcrResponse:
    path = Path(req.file_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"file not found: {req.file_path}")

    images = _load_images(path)
    raw = _run_model(images)

    parsed = _try_extract_json(raw)
    if parsed is not None:
        try:
            expense = Expense(**parsed)
            return OcrResponse(structured=expense, rawText=raw, confidence=0.9)
        except Exception as exc:  # noqa: BLE001
            logger.warning("structured parse failed: %s", exc)

    return OcrResponse(structured=None, rawText=raw, confidence=0.4)

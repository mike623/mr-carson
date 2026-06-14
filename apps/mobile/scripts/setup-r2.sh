#!/usr/bin/env bash
# Host the Mr. Carson on-device model on Cloudflare R2 (tokenless public URL).
#
# Prereqs (one-time, YOU do these — they need a browser):
#   1. A free Cloudflare account.
#   2. `wrangler login`  (interactive OAuth — run it yourself).
#   3. An R2 API token (dashboard → R2 → Manage API Tokens) for the rclone
#      upload — gives an Access Key ID + Secret. Export them below.
#   4. The model file present locally as $MODEL_FILE (download once from
#      HuggingFace with your HF token, or a non-gated LiteRT mirror).
#
# wrangler can only PUT files <315 MB, so the ~3 GB model is uploaded with
# rclone (S3-compatible). wrangler is used for the bucket + public URL.
set -euo pipefail

# ---- config (edit these) ---------------------------------------------------
BUCKET="${BUCKET:-mr-carson-models}"
MODEL_FILE="${MODEL_FILE:-/Users/mikewong/mr-carson-models/gemma-4-E2B-it.litertlm}"
OBJECT_KEY="${OBJECT_KEY:-gemma-4-e2b.litertlm}"
# R2 S3 credentials (from the dashboard API token) + account id:
: "${R2_ACCOUNT_ID:?set R2_ACCOUNT_ID}"
: "${R2_ACCESS_KEY_ID:?set R2_ACCESS_KEY_ID}"
: "${R2_SECRET_ACCESS_KEY:?set R2_SECRET_ACCESS_KEY}"
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"

echo "==> 1/4  create bucket ($BUCKET)"
wrangler r2 bucket create "$BUCKET" || echo "   (bucket may already exist — continuing)"

echo "==> 2/4  enable public dev URL"
wrangler r2 bucket dev-url enable "$BUCKET"

echo "==> 3/4  upload model via rclone ($MODEL_FILE → $BUCKET/$OBJECT_KEY)"
[ -f "$MODEL_FILE" ] || { echo "ERROR: $MODEL_FILE not found — download the model first"; exit 1; }
rclone copyto "$MODEL_FILE" \
  ":s3,provider=Cloudflare,access_key_id=${R2_ACCESS_KEY_ID},secret_access_key=${R2_SECRET_ACCESS_KEY},endpoint=${R2_ENDPOINT}:${BUCKET}/${OBJECT_KEY}" \
  --progress --s3-no-check-bucket

echo "==> 4/4  done"
echo
echo "Public URL (set as kDefaultModelUrl in lib/ai/gemma_service.dart):"
echo "  https://pub-<hash>.r2.dev/${OBJECT_KEY}"
echo "  (the exact pub-<hash> host is printed by step 2 above)"
echo
echo "Remember: drop the Gemma Terms of Use + Prohibited Use Policy in the bucket"
echo "alongside the model (redistribution requirement)."

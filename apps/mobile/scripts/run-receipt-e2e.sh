#!/usr/bin/env bash
# One-shot real-model receipt e2e on a physical iOS device.
#
#   ./scripts/run-receipt-e2e.sh [device-id]
#
# Auto-detects the first connected physical iPhone if no id is given.
# Drives: onboarding → download/load Gemma → upload receipt → real OCR →
# confirm → ledger. Screenshots land in build/e2e_screenshots/.
#
# One-time setup NOT automatable here (macOS/Apple gates):
#   - Xcode → Settings → Accounts: sign in (dev signing)
#   - System Settings → Privacy & Security → Local Network: allow your terminal
#   - iPhone: Developer Mode on, unlocked, Auto-Lock = Never, plugged in
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-$(flutter devices --machine 2>/dev/null | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: d = []
ios = [x for x in d if str(x.get("targetPlatform","")).startswith("ios") and not x.get("emulator", True)]
print(ios[0]["id"] if ios else "")
')}"

if [ -z "$DEVICE" ]; then
  echo "No physical iOS device found. Plug in + unlock the iPhone." >&2
  exit 1
fi
echo "▶ Device: $DEVICE"

# Xcode holding a debug session collides with flutter's attach.
if pgrep -f "Xcode.app/Contents/MacOS/Xcode" >/dev/null 2>&1; then
  echo "⚠  Xcode is running — quit it (⌘Q); its debugger blocks flutter attach." >&2
fi

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/receipt_e2e_test.dart \
  -d "$DEVICE" --profile

echo "✓ Screenshots: $(pwd)/build/e2e_screenshots/"

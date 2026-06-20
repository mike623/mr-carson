# Online/Offline Model Selection — Phase 1 (Cloud OCR) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose Offline (on-device Gemma) vs Online (cloud OpenRouter via a proxy) for receipt OCR, persisted across launches, defaulting safely based on whether the device can run the on-device model.

**Architecture:** A single persisted `ModelMode` (auto/offline/online) drives a runtime backend choice. `receiptOcrEngineProvider` resolves to the existing on-device `GemmaOcrEngine` or a new `CloudOcrEngine` that POSTs OpenAI-format vision requests to a Cloudflare Worker proxy, which injects the OpenRouter API key server-side. Device capability (simulator / OS floor) decides the `auto` default. The API key never ships in the app.

**Tech Stack:** Flutter, Riverpod, `shared_preferences` (persist choice), `device_info_plus` (capability), `dart:io` HttpClient (no HTTP SDK), Cloudflare Worker + `wrangler` (proxy), OpenRouter (OpenAI-compatible).

## Global Constraints

- This is **Phase 1 only**: receipt OCR. The Ask/Q&A chat engine stays on-device this phase (separate plan: `2026-06-XX-online-offline-chat.md`).
- **Privacy default is offline-first.** Online is opt-in and requires an explicit one-time consent confirmation. The Settings "Discretion" copy must NOT claim "everything stays on this phone / no cloud" while Online is active.
- **API key is server-side only** (Cloudflare Worker secret `OPENROUTER_API_KEY`). Never embed it in the app or commit it.
- Proxy URL is non-secret config: `--dart-define=OCR_PROXY_URL=...` (default `http://localhost:8787` for local `wrangler dev`).
- Cloud model: `--dart-define=OCR_CLOUD_MODEL=...`, default `google/gemini-2.5-flash` (vision-capable, cheap).
- Reuse the existing `ReceiptOcrEngine` seam (`lib/ai/receipt_ocr_engine.dart`) and the existing tolerant parse (`ReceiptPipelineService.coerceDraftJson`) — the cloud path returns the same raw-text contract as Gemma/Ollama.
- New deps must be first-party Flutter Favorites: `shared_preferences`, `device_info_plus`. No other new deps.
- All Dart commands run from `apps/mobile/`. Tests: `flutter test`. Analyze: `flutter analyze lib/`.
- Commit after every task (frequent commits).

---

## File Structure

- `infrastructure/openrouter-proxy/wrangler.toml` — Worker config (NEW)
- `infrastructure/openrouter-proxy/src/worker.js` — OpenAI-compatible passthrough that injects the key (NEW)
- `infrastructure/openrouter-proxy/README.md` — deploy + local-dev instructions (NEW)
- `apps/mobile/lib/ai/model_mode.dart` — `ModelMode` enum, `Backend` enum, `resolveBackend`, persisted `modelModeProvider`, `sharedPreferencesProvider` (NEW)
- `apps/mobile/lib/ai/device_capability.dart` — `DeviceCapability`, pure `capabilityFrom(...)`, async `detectCapability(...)`, `deviceCapabilityProvider` (NEW)
- `apps/mobile/lib/ai/receipt_ocr_engine.dart` — add `JsonPoster` typedef, `defaultJsonPoster`, `CloudOcrEngine`; rewrite `receiptOcrEngineProvider` to select by `ModelMode`+capability (MODIFY)
- `apps/mobile/lib/main.dart` — load `SharedPreferences`, detect capability, seed providers (MODIFY)
- `apps/mobile/lib/features/settings/settings_screen.dart` — add "Where he thinks" section + consent + conditional Discretion copy (MODIFY)
- `apps/mobile/test/ai/model_mode_test.dart` — `resolveBackend` + persistence (NEW)
- `apps/mobile/test/ai/device_capability_test.dart` — `capabilityFrom` (NEW)
- `apps/mobile/test/ai/cloud_ocr_engine_test.dart` — `CloudOcrEngine` with fake poster (NEW)
- `apps/mobile/test/ai/receipt_ocr_engine_selection_test.dart` — provider selection (NEW)
- `apps/mobile/test/features/settings/model_mode_settings_test.dart` — Settings widget (NEW)

---

## Task 1: Cloudflare Worker proxy

**Files:**
- Create: `infrastructure/openrouter-proxy/wrangler.toml`
- Create: `infrastructure/openrouter-proxy/src/worker.js`
- Create: `infrastructure/openrouter-proxy/README.md`

**Interfaces:**
- Produces: an HTTP endpoint `POST {proxyUrl}/v1/chat/completions` accepting an OpenAI chat-completions body and returning OpenRouter's JSON verbatim. The Dart `CloudOcrEngine` (Task 6) consumes this exact shape.

- [ ] **Step 1: Write the Worker config**

`infrastructure/openrouter-proxy/wrangler.toml`:
```toml
name = "mr-carson-openrouter-proxy"
main = "src/worker.js"
compatibility_date = "2024-11-01"

# Set the secret (never commit it):
#   wrangler secret put OPENROUTER_API_KEY
```

- [ ] **Step 2: Write the Worker**

`infrastructure/openrouter-proxy/src/worker.js`:
```js
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
```

- [ ] **Step 3: Write the README**

`infrastructure/openrouter-proxy/README.md`:
```markdown
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
  -d '{"model":"google/gemini-2.5-flash","messages":[{"role":"user","content":"say ok"}]}' \
  | head -c 300
```
Expect a JSON body containing `"choices"`.
```

- [ ] **Step 4: Smoke test locally**

Run (in one shell): `cd infrastructure/openrouter-proxy && echo 'OPENROUTER_API_KEY=<your-key>' > .dev.vars && wrangler dev`
Run (in another shell):
```bash
curl -s http://localhost:8787/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"google/gemini-2.5-flash","messages":[{"role":"user","content":"say ok"}]}' | head -c 300
```
Expected: JSON containing `"choices"` and a message with "ok".

- [ ] **Step 5: Commit**

```bash
echo "infrastructure/openrouter-proxy/.dev.vars" >> .gitignore
echo "infrastructure/openrouter-proxy/node_modules/" >> .gitignore
git add infrastructure/openrouter-proxy .gitignore
git commit -m "feat(infra): OpenRouter auth proxy (Cloudflare Worker)"
```

---

## Task 2: SharedPreferences provider + dependency

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Create: `apps/mobile/lib/ai/model_mode.dart` (the `sharedPreferencesProvider` part only this task)

**Interfaces:**
- Produces: `final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());` — overridden in `main()` and in tests. Tasks 3 reads it.

- [ ] **Step 1: Add the dependency**

Run: `cd apps/mobile && flutter pub add shared_preferences`
Expected: `pubspec.yaml` gains `shared_preferences:` and `flutter pub get` succeeds.

- [ ] **Step 2: Create the provider stub**

`apps/mobile/lib/ai/model_mode.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the [SharedPreferences] instance. Overridden in `main()` (after
/// `SharedPreferences.getInstance()`) and in tests with an in-memory instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider in main()'),
);
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/ai/model_mode.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/ai/model_mode.dart
git commit -m "feat(mobile): add shared_preferences + provider stub"
```

---

## Task 3: ModelMode enum, Backend enum, resolveBackend, persisted provider

**Files:**
- Modify: `apps/mobile/lib/ai/model_mode.dart`
- Test: `apps/mobile/test/ai/model_mode_test.dart`

**Interfaces:**
- Consumes: `sharedPreferencesProvider` (Task 2); `DeviceCapability` (Task 4) — for the test of `resolveBackend` you may construct `DeviceCapability` directly.
- Produces:
  - `enum ModelMode { auto, offline, online }`
  - `enum Backend { offline, online }`
  - `Backend resolveBackend(ModelMode mode, DeviceCapability cap)`
  - `final modelModeProvider = NotifierProvider<ModelModeNotifier, ModelMode>(ModelModeNotifier.new);`
  - `class ModelModeNotifier extends Notifier<ModelMode> { void set(ModelMode m); }`

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/ai/model_mode_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/device_capability.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const capable = DeviceCapability(canRunOffline: true, reason: '');
  const incapable = DeviceCapability(canRunOffline: false, reason: 'sim');

  test('resolveBackend honours explicit modes', () {
    expect(resolveBackend(ModelMode.offline, incapable), Backend.offline);
    expect(resolveBackend(ModelMode.online, capable), Backend.online);
  });

  test('auto resolves by capability', () {
    expect(resolveBackend(ModelMode.auto, capable), Backend.offline);
    expect(resolveBackend(ModelMode.auto, incapable), Backend.online);
  });

  test('modelModeProvider persists the choice', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);

    expect(c.read(modelModeProvider), ModelMode.auto); // default
    c.read(modelModeProvider.notifier).set(ModelMode.online);
    expect(c.read(modelModeProvider), ModelMode.online);
    expect(prefs.getString('model_mode'), 'online');

    // A fresh container reading the same prefs restores the choice.
    final c2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    expect(c2.read(modelModeProvider), ModelMode.online);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai/model_mode_test.dart`
Expected: FAIL — `ModelMode`/`resolveBackend`/`modelModeProvider` not defined (and `device_capability.dart` missing; Task 4 creates it — if running strictly in order, write Task 4 first or stub `DeviceCapability` here. The plan orders Task 4 before finalizing; for this step the compile error is the expected failure).

- [ ] **Step 3: Implement**

Append to `apps/mobile/lib/ai/model_mode.dart`:
```dart
import 'device_capability.dart';

/// User-chosen inference location. Persisted across launches.
enum ModelMode { auto, offline, online }

/// The resolved backend after applying device capability to a [ModelMode].
enum Backend { offline, online }

/// Resolves the concrete backend. `auto` picks offline when the device can run
/// the on-device model, otherwise online.
Backend resolveBackend(ModelMode mode, DeviceCapability cap) {
  switch (mode) {
    case ModelMode.offline:
      return Backend.offline;
    case ModelMode.online:
      return Backend.online;
    case ModelMode.auto:
      return cap.canRunOffline ? Backend.offline : Backend.online;
  }
}

const _kModelModeKey = 'model_mode';

class ModelModeNotifier extends Notifier<ModelMode> {
  @override
  ModelMode build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_kModelModeKey);
    return ModelMode.values.where((m) => m.name == raw).firstOrNull ??
        ModelMode.auto;
  }

  void set(ModelMode mode) {
    ref.read(sharedPreferencesProvider).setString(_kModelModeKey, mode.name);
    state = mode;
  }
}

final modelModeProvider =
    NotifierProvider<ModelModeNotifier, ModelMode>(ModelModeNotifier.new);
```
> Note: `firstOrNull` comes from `package:collection`, already a transitive dep; if analyze complains, add `import 'package:collection/collection.dart';`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai/model_mode_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ai/model_mode.dart test/ai/model_mode_test.dart
git commit -m "feat(mobile): persisted ModelMode + resolveBackend"
```

---

## Task 4: Device capability detection

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (add `device_info_plus`)
- Create: `apps/mobile/lib/ai/device_capability.dart`
- Test: `apps/mobile/test/ai/device_capability_test.dart`

**Interfaces:**
- Produces:
  - `class DeviceCapability { const DeviceCapability({required bool canRunOffline, required String reason}); }`
  - `DeviceCapability capabilityFrom({required bool isPhysicalDevice, required bool isIOS, int? iosMajorVersion, int? androidSdk})`
  - `Future<DeviceCapability> detectCapability({DeviceInfoPlugin? deviceInfo})`
  - `final deviceCapabilityProvider = StateProvider<DeviceCapability>((ref) => const DeviceCapability(canRunOffline: true, reason: ''));`

- [ ] **Step 1: Add the dependency**

Run: `cd apps/mobile && flutter pub add device_info_plus`
Expected: `pubspec.yaml` gains `device_info_plus:`.

- [ ] **Step 2: Write the failing test**

`apps/mobile/test/ai/device_capability_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/device_capability.dart';

void main() {
  test('simulator/emulator cannot run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: false, isIOS: true, iosMajorVersion: 18);
    expect(cap.canRunOffline, isFalse);
    expect(cap.reason, contains('imulator'));
  });

  test('modern physical iPhone can run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: true, iosMajorVersion: 17);
    expect(cap.canRunOffline, isTrue);
  });

  test('old iOS cannot run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: true, iosMajorVersion: 14);
    expect(cap.canRunOffline, isFalse);
  });

  test('modern physical Android can run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: false, androidSdk: 30);
    expect(cap.canRunOffline, isTrue);
  });

  test('old Android cannot run offline', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: false, androidSdk: 24);
    expect(cap.canRunOffline, isFalse);
  });

  test('unknown version is conservatively incapable', () {
    final cap = capabilityFrom(
      isPhysicalDevice: true, isIOS: true, iosMajorVersion: null);
    expect(cap.canRunOffline, isFalse);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/ai/device_capability_test.dart`
Expected: FAIL — `device_capability.dart` not found.

- [ ] **Step 4: Implement**

`apps/mobile/lib/ai/device_capability.dart`:
```dart
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this device can realistically run the on-device Gemma model.
class DeviceCapability {
  const DeviceCapability({required this.canRunOffline, required this.reason});

  final bool canRunOffline;

  /// Human-readable explanation, shown as a Settings hint when false.
  final String reason;
}

// Floors below which the on-device model is unreliable / unsupported.
const _kIosMinMajor = 16;
const _kAndroidMinSdk = 26; // Android 8.0

/// Pure capability rule — unit-testable without platform channels.
///
/// Note: this is a coarse gate (simulator + OS floor). Exact RAM/storage isn't
/// available cross-platform via device_info_plus; the real failure signal is a
/// runtime load failure, handled separately by recording it and switching the
/// effective mode. // ponytail: OS-floor heuristic; add RAM probe if false
/// negatives show up.
DeviceCapability capabilityFrom({
  required bool isPhysicalDevice,
  required bool isIOS,
  int? iosMajorVersion,
  int? androidSdk,
}) {
  if (!isPhysicalDevice) {
    return const DeviceCapability(
      canRunOffline: false,
      reason: 'The simulator can\'t run the on-device model — use Online here.',
    );
  }
  if (isIOS) {
    if (iosMajorVersion == null) {
      return const DeviceCapability(
          canRunOffline: false, reason: 'Unknown iOS version.');
    }
    return iosMajorVersion >= _kIosMinMajor
        ? const DeviceCapability(canRunOffline: true, reason: '')
        : const DeviceCapability(
            canRunOffline: false, reason: 'iOS $_kIosMinMajor or newer needed.');
  }
  if (androidSdk == null) {
    return const DeviceCapability(
        canRunOffline: false, reason: 'Unknown Android version.');
  }
  return androidSdk >= _kAndroidMinSdk
      ? const DeviceCapability(canRunOffline: true, reason: '')
      : const DeviceCapability(
          canRunOffline: false, reason: 'Android 8 or newer needed.');
}

/// Gathers platform facts and applies [capabilityFrom].
Future<DeviceCapability> detectCapability({DeviceInfoPlugin? deviceInfo}) async {
  final info = deviceInfo ?? DeviceInfoPlugin();
  if (Platform.isIOS) {
    final ios = await info.iosInfo;
    final major = int.tryParse(ios.systemVersion.split('.').first);
    return capabilityFrom(
      isPhysicalDevice: ios.isPhysicalDevice,
      isIOS: true,
      iosMajorVersion: major,
    );
  }
  if (Platform.isAndroid) {
    final android = await info.androidInfo;
    return capabilityFrom(
      isPhysicalDevice: android.isPhysicalDevice,
      isIOS: false,
      androidSdk: android.version.sdkInt,
    );
  }
  // Desktop/web (e.g. running tests on host): treat as incapable → online.
  return const DeviceCapability(
      canRunOffline: false, reason: 'On-device model not supported here.');
}

/// Current capability. Seeded conservatively; `main()` refines it after
/// [detectCapability]. Recorded runtime load failures can also flip it false.
final deviceCapabilityProvider = StateProvider<DeviceCapability>(
  (ref) => const DeviceCapability(canRunOffline: true, reason: ''),
);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/ai/device_capability_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/ai/device_capability.dart test/ai/device_capability_test.dart
git commit -m "feat(mobile): device capability detection for offline model"
```

---

## Task 5: JsonPoster seam + CloudOcrEngine

**Files:**
- Modify: `apps/mobile/lib/ai/receipt_ocr_engine.dart`
- Test: `apps/mobile/test/ai/cloud_ocr_engine_test.dart`

**Interfaces:**
- Consumes: existing `ReceiptOcrEngine` abstract class (`readReceipt({required String prompt, required Uint8List imageBytes})`).
- Produces:
  - `typedef JsonPoster = Future<Map<String, dynamic>> Function(Uri url, Map<String, dynamic> body);`
  - `Future<Map<String, dynamic>> defaultJsonPoster(Uri url, Map<String, dynamic> body);`
  - `class CloudOcrEngine implements ReceiptOcrEngine { CloudOcrEngine({required String proxyUrl, required String model, JsonPoster? poster}); }`

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/ai/cloud_ocr_engine_test.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/receipt_ocr_engine.dart';

void main() {
  test('CloudOcrEngine posts OpenAI vision payload and returns content',
      () async {
    late Uri capturedUrl;
    late Map<String, dynamic> capturedBody;

    final engine = CloudOcrEngine(
      proxyUrl: 'http://localhost:8787',
      model: 'google/gemini-2.5-flash',
      poster: (url, body) async {
        capturedUrl = url;
        capturedBody = body;
        return {
          'choices': [
            {'message': {'content': '{"merchant":"Tesco","total":9.99}'}}
          ]
        };
      },
    );

    final out = await engine.readReceipt(
      prompt: 'extract',
      imageBytes: Uint8List.fromList([1, 2, 3]),
    );

    expect(out, '{"merchant":"Tesco","total":9.99}');
    expect(capturedUrl.toString(), 'http://localhost:8787/v1/chat/completions');
    expect(capturedBody['model'], 'google/gemini-2.5-flash');
    final content = (capturedBody['messages'] as List).first['content'] as List;
    expect(content[0]['type'], 'text');
    expect(content[0]['text'], 'extract');
    expect(content[1]['type'], 'image_url');
    expect(content[1]['image_url']['url'], startsWith('data:image/jpeg;base64,'));
  });

  test('CloudOcrEngine returns empty string when no choices', () async {
    final engine = CloudOcrEngine(
      proxyUrl: 'http://x',
      model: 'm',
      poster: (_, __) async => {'choices': []},
    );
    final out = await engine.readReceipt(
      prompt: 'p', imageBytes: Uint8List(0));
    expect(out, '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai/cloud_ocr_engine_test.dart`
Expected: FAIL — `CloudOcrEngine` not defined.

- [ ] **Step 3: Implement**

Add to `apps/mobile/lib/ai/receipt_ocr_engine.dart` (after the existing `OllamaOcrEngine`):
```dart
/// Posts a JSON body and returns the decoded JSON object. Default transport for
/// [CloudOcrEngine]; injectable for tests.
typedef JsonPoster = Future<Map<String, dynamic>> Function(
    Uri url, Map<String, dynamic> body);

/// Default [JsonPoster] over dart:io HttpClient (no HTTP package dependency).
Future<Map<String, dynamic>> defaultJsonPoster(
    Uri url, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) {
      throw HttpException('Proxy ${resp.statusCode}: $text');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// Cloud OCR backend — sends the receipt to an OpenAI-compatible proxy
/// (Cloudflare Worker → OpenRouter). The proxy holds the API key.
class CloudOcrEngine implements ReceiptOcrEngine {
  CloudOcrEngine({
    required this.proxyUrl,
    required this.model,
    JsonPoster? poster,
  }) : _post = poster ?? defaultJsonPoster;

  final String proxyUrl;
  final String model;
  final JsonPoster _post;

  @override
  Future<String> readReceipt({
    required String prompt,
    required Uint8List imageBytes,
  }) async {
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';
    final json = await _post(Uri.parse('$proxyUrl/v1/chat/completions'), {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {'type': 'image_url', 'image_url': {'url': dataUrl}},
          ],
        }
      ],
    });
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = choices.first;
      if (msg is Map) {
        final content = (msg['message'] as Map?)?['content'];
        if (content is String) return content;
      }
    }
    return '';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai/cloud_ocr_engine_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/ai/receipt_ocr_engine.dart test/ai/cloud_ocr_engine_test.dart
git commit -m "feat(mobile): CloudOcrEngine (OpenAI vision via proxy)"
```

---

## Task 6: Runtime backend selection in receiptOcrEngineProvider

**Files:**
- Modify: `apps/mobile/lib/ai/receipt_ocr_engine.dart`
- Test: `apps/mobile/test/ai/receipt_ocr_engine_selection_test.dart`

**Interfaces:**
- Consumes: `modelModeProvider`, `deviceCapabilityProvider`, `resolveBackend` (Tasks 3–4); `CloudOcrEngine`, `GemmaOcrEngine` (Task 5 + existing).
- Produces: a rewritten `receiptOcrEngineProvider` that returns `CloudOcrEngine` when `resolveBackend(...) == Backend.online`, else `GemmaOcrEngine`. Cloud config from dart-defines `OCR_PROXY_URL` (default `http://localhost:8787`) and `OCR_CLOUD_MODEL` (default `google/gemini-2.5-flash`).

- [ ] **Step 1: Write the failing test**

`apps/mobile/test/ai/receipt_ocr_engine_selection_test.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/device_capability.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/ai/receipt_ocr_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(List<Override> extra) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs), ...extra],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('online mode yields CloudOcrEngine', () async {
    final c = await _container([]);
    c.read(modelModeProvider.notifier).set(ModelMode.online);
    expect(c.read(receiptOcrEngineProvider), isA<CloudOcrEngine>());
  });

  test('offline mode yields GemmaOcrEngine', () async {
    final c = await _container([]);
    c.read(modelModeProvider.notifier).set(ModelMode.offline);
    expect(c.read(receiptOcrEngineProvider), isA<GemmaOcrEngine>());
  });

  test('auto + incapable device yields CloudOcrEngine', () async {
    final c = await _container([]);
    c.read(deviceCapabilityProvider.notifier).state =
        const DeviceCapability(canRunOffline: false, reason: 'sim');
    // mode defaults to auto
    expect(c.read(receiptOcrEngineProvider), isA<CloudOcrEngine>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ai/receipt_ocr_engine_selection_test.dart`
Expected: FAIL — current provider always returns Gemma (ignores mode); the online/auto tests fail.

- [ ] **Step 3: Implement**

In `apps/mobile/lib/ai/receipt_ocr_engine.dart`:
- Add imports near the top (with the others):
```dart
import 'device_capability.dart';
import 'model_mode.dart';
```
- Replace the existing `_ocrBackend`/`receiptOcrEngineProvider` block with:
```dart
const String _ollamaBaseUrl = String.fromEnvironment(
  'OLLAMA_BASE_URL',
  defaultValue: 'http://localhost:11434',
);
const String _ollamaModel =
    String.fromEnvironment('OLLAMA_MODEL', defaultValue: 'gemma3');
const String _ocrProxyUrl = String.fromEnvironment(
  'OCR_PROXY_URL',
  defaultValue: 'http://localhost:8787',
);
const String _ocrCloudModel = String.fromEnvironment(
  'OCR_CLOUD_MODEL',
  defaultValue: 'google/gemini-2.5-flash',
);
// Dev escape hatch: force the local Ollama backend regardless of ModelMode.
const String _ocrBackendOverride =
    String.fromEnvironment('OCR_BACKEND', defaultValue: '');

/// Selects the OCR backend at runtime from the user's [ModelMode] and the
/// device's [DeviceCapability]. `--dart-define=OCR_BACKEND=ollama` forces the
/// local Ollama dev backend.
final receiptOcrEngineProvider = Provider<ReceiptOcrEngine>((ref) {
  if (_ocrBackendOverride == 'ollama') {
    return OllamaOcrEngine(baseUrl: _ollamaBaseUrl, model: _ollamaModel);
  }
  final mode = ref.watch(modelModeProvider);
  final cap = ref.watch(deviceCapabilityProvider);
  if (resolveBackend(mode, cap) == Backend.online) {
    return CloudOcrEngine(proxyUrl: _ocrProxyUrl, model: _ocrCloudModel);
  }
  return GemmaOcrEngine(ref.watch(gemmaServiceProvider));
});
```
> This removes the old compile-time-only `OCR_BACKEND=gemma|ollama` selection and replaces it with runtime selection (Ollama kept as a forced dev override).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ai/receipt_ocr_engine_selection_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Regression — run the existing OCR/pipeline tests**

Run: `flutter test test/ai/ test/data/receipt_pipeline_integration_test.dart test/features/shell/ test/features/confirm/`
Expected: All pass. (These construct engines directly or via overrides and must be unaffected.)

- [ ] **Step 6: Commit**

```bash
git add lib/ai/receipt_ocr_engine.dart test/ai/receipt_ocr_engine_selection_test.dart
git commit -m "feat(mobile): runtime OCR backend selection by ModelMode + capability"
```

---

## Task 7: Wire main() — load prefs, detect capability, seed providers

**Files:**
- Modify: `apps/mobile/lib/main.dart`

**Interfaces:**
- Consumes: `sharedPreferencesProvider`, `deviceCapabilityProvider` (Tasks 2,4), `detectCapability` (Task 4).
- Produces: a running app where the prefs instance is provided and capability is detected at startup.

- [ ] **Step 1: Update main()**

In `apps/mobile/lib/main.dart`, add imports:
```dart
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/device_capability.dart';
import 'ai/model_mode.dart';
```
Replace the `appRunner` so the ProviderScope is built with overrides and capability is detected first. Change:
```dart
  await FlutterGemma.initialize();
```
to:
```dart
  await FlutterGemma.initialize();

  final prefs = await SharedPreferences.getInstance();
  final capability = await detectCapability();
```
and change the `appRunner` line:
```dart
    appRunner: () => runApp(const ProviderScope(child: MrCarsonApp())),
```
to:
```dart
    appRunner: () => runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceCapabilityProvider.overrideWith((ref) => capability),
        ],
        child: const MrCarsonApp(),
      ),
    ),
```

- [ ] **Step 2: Analyze + run the full suite**

Run: `flutter analyze lib/ && flutter test`
Expected: No issues; all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(mobile): seed prefs + device capability at startup"
```

---

## Task 8: Settings UI — "Where he thinks" + consent + conditional privacy copy

**Files:**
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart`
- Test: `apps/mobile/test/features/settings/model_mode_settings_test.dart`

**Interfaces:**
- Consumes: `modelModeProvider`, `deviceCapabilityProvider` (Tasks 3,4).
- Produces: a new Settings section letting the user pick Auto / Offline / Online (segmented control like `_CurrencyRow`), a one-time consent confirm when switching to Online, a capability hint when the device can't run offline, and Discretion copy that reflects the active mode.

- [ ] **Step 1: Write the failing widget test**

`apps/mobile/test/features/settings/model_mode_settings_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the model-location section', (tester) async {
    await _pump(tester);
    expect(find.text('Where he thinks'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('switching to Online asks for consent then applies', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    // A consent dialog appears.
    expect(find.textContaining('leaves your phone'), findsOneWidget);
    await tester.tap(find.text('Use Online'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(modelModeProvider), ModelMode.online);
  });

  testWidgets('declining consent leaves mode unchanged', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep offline'));
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(modelModeProvider), isNot(ModelMode.online));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/settings/model_mode_settings_test.dart`
Expected: FAIL — "Where he thinks" not found.

- [ ] **Step 3: Implement the section**

In `apps/mobile/lib/features/settings/settings_screen.dart`:
- Add import:
```dart
import 'package:mr_carson/ai/model_mode.dart';
import 'package:mr_carson/ai/device_capability.dart';
```
- In `SettingsScreen.build`, insert after the `_ModelCard(...)` widget (inside the children list, right after the "Mr. Carson's mind" model card):
```dart
                  const SizedBox(height: 18),
                  const _SectionLabel('Where he thinks'),
                  const _ModelLocationCard(),
```
- Add these widgets at the end of the file:
```dart
/// Segmented Auto / Offline / Online control with consent + capability hint.
class _ModelLocationCard extends ConsumerWidget {
  const _ModelLocationCard();

  static const _modes = [
    (mode: ModelMode.auto, label: 'Auto'),
    (mode: ModelMode.offline, label: 'Offline'),
    (mode: ModelMode.online, label: 'Online'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(modelModeProvider);
    final cap = ref.watch(deviceCapabilityProvider);

    return Container(
      decoration: BoxDecoration(
        color: MrCarsonColors.surface,
        border: Border.all(color: MrCarsonColors.line, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reads receipts', style: MrCarsonType.ui(size: 14.5)),
          const SizedBox(height: 2),
          Text(
            'Offline keeps everything on this phone. Online is faster and works '
            'on any device, but sends the receipt to our server to be read.',
            style: MrCarsonType.ui(size: 12, color: MrCarsonColors.ink3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final m in _modes)
                Padding(
                  padding: EdgeInsets.only(left: m == _modes.first ? 0 : 6),
                  child: _ModeButton(
                    label: m.label,
                    selected: m.mode == selected,
                    onTap: () => _choose(context, ref, m.mode),
                  ),
                ),
            ],
          ),
          if (!cap.canRunOffline && cap.reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              cap.reason,
              style: MrCarsonType.ui(size: 11.5, color: MrCarsonColors.warn),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _choose(
      BuildContext context, WidgetRef ref, ModelMode mode) async {
    if (mode == ModelMode.online) {
      final ok = await _confirmOnline(context);
      if (ok != true) return;
    }
    ref.read(modelModeProvider.notifier).set(mode);
  }

  Future<bool?> _confirmOnline(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MrCarsonColors.surface,
        title: Text('Read receipts online?',
            style: MrCarsonType.ui(size: 16, weight: FontWeight.w600)),
        content: Text(
          'With Online, the receipt image leaves your phone and is sent to our '
          'server to be read. Nothing is stored there. You can switch back to '
          'Offline at any time.',
          style: MrCarsonType.ui(size: 13.5, color: MrCarsonColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep offline',
                style: MrCarsonType.ui(color: MrCarsonColors.ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Use Online',
                style: MrCarsonType.ui(
                    color: MrCarsonColors.accent, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? MrCarsonColors.accent : MrCarsonColors.bg,
          border: Border.all(color: MrCarsonColors.line, width: 1),
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: MrCarsonType.ui(
            size: 13.5,
            weight: FontWeight.w600,
            color: selected ? MrCarsonColors.accentInk : MrCarsonColors.ink2,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Make the Discretion copy conditional**

Convert `_DiscretionCard` from `StatelessWidget` to `ConsumerWidget` so it reflects the mode. Replace its class declaration and `build` signature:
```dart
class _DiscretionCard extends ConsumerWidget {
  const _DiscretionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modelModeProvider);
    final cap = ref.watch(deviceCapabilityProvider);
    final online = resolveBackend(mode, cap) == Backend.online;
```
Then replace the two `_row(...)` calls inside it with:
```dart
          _row(
            dot: online ? MrCarsonColors.warn : MrCarsonColors.grocery,
            label: online
                ? 'Receipts are read online when needed'
                : 'Everything stays on this phone',
            trailing: online ? 'Online' : 'Always',
            border: true,
          ),
          _row(
            dot: MrCarsonColors.transport,
            label: online
                ? 'No account — only receipt images are sent'
                : 'No account, no cloud, no sign-in',
            trailing: '—',
            border: false,
          ),
```

- [ ] **Step 5: Run the widget test**

Run: `flutter test test/features/settings/model_mode_settings_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 6: Analyze + full suite**

Run: `flutter analyze lib/ && flutter test`
Expected: No issues; all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/settings/settings_screen.dart test/features/settings/model_mode_settings_test.dart
git commit -m "feat(mobile): Settings model-location picker + consent + honest privacy copy"
```

---

## Task 9: Manual simulator end-to-end via wrangler dev

**Files:** none (verification task)

**Interfaces:** Consumes everything above.

- [ ] **Step 1: Start the proxy locally**

Run: `cd infrastructure/openrouter-proxy && wrangler dev`
Expected: serving on `http://localhost:8787` (with `.dev.vars` holding `OPENROUTER_API_KEY`).

- [ ] **Step 2: Launch the app on the simulator pointed at the proxy**

Run:
```bash
cd apps/mobile && flutter run -d <ios-simulator-id> \
  --dart-define=OCR_PROXY_URL=http://localhost:8787 \
  --dart-define=OCR_CLOUD_MODEL=google/gemini-2.5-flash
```
Expected: app launches. Because it's a simulator, `deviceCapabilityProvider.canRunOffline` is false, so `Auto` already resolves to Online.

- [ ] **Step 3: Verify the flow**

- Open Settings → "Where he thinks" → confirm the capability hint shows (simulator) and pick **Online** (accept consent).
- Confirm the Discretion card flips to the "read online" copy.
- Go to add → Upload from library → choose a real receipt image.
- Expected: pending card appears, then a populated Confirm screen (merchant, total, line items) read by the cloud model — not the "Item / 0.00" placeholders.
- Check the `wrangler dev` console shows the forwarded request.

- [ ] **Step 4: Verify offline path is untouched**

- In Settings switch back to **Offline**.
- Expected: upload now uses the on-device path (on a simulator this will fail to load the model — that's expected and is exactly why Auto picked Online).

- [ ] **Step 5: (No commit — verification only.) Record the outcome in the PR description.**

---

## Self-Review

**1. Spec coverage:**
- "CloudOcrEngine via proxy" → Tasks 1, 5, 6. ✔
- "user opt-in to control on setting online/offline" → Tasks 3, 8 (segmented control + persistence + consent). ✔
- "detect if device able to download offline" → Task 4 (`capabilityFrom`/`detectCapability`) + Auto resolution (Task 3) + Settings hint (Task 8). ✔
- "test locally via sim with CF worker" → Tasks 1 (wrangler dev) + 9 (sim run with `OCR_PROXY_URL`). ✔
- "same model as the Q&A engine" → **explicitly deferred** to Phase 2 (Global Constraints + a separate plan). Phase 1 covers OCR only; the `ModelMode` provider is built to be reused by the chat backend in Phase 2. ✔ (flagged, not silently dropped)

**2. Placeholder scan:** No TBD/TODO/"add error handling" — all steps contain concrete code and commands. ✔

**3. Type consistency:**
- `DeviceCapability({required bool canRunOffline, required String reason})` — same in Tasks 3,4,6,8. ✔
- `ModelMode { auto, offline, online }` / `Backend { offline, online }` / `resolveBackend(ModelMode, DeviceCapability)` — consistent across Tasks 3,6,8. ✔
- `CloudOcrEngine({required String proxyUrl, required String model, JsonPoster? poster})` — same in Tasks 5,6. ✔
- `sharedPreferencesProvider` / `deviceCapabilityProvider` / `modelModeProvider` — names consistent across Tasks 2–8. ✔
- Engine contract `readReceipt({required String prompt, required Uint8List imageBytes})` matches the existing `ReceiptOcrEngine`. ✔

---

## Phase 2 (separate plan, not this document)
Cloud Q&A chat: extract a `ChatBackend` interface from `ChatService` (763 lines), add `CloudChatService` (OpenRouter streaming SSE + OpenAI tools loop reusing the existing tool schemas + `_runTool`), and have the chat provider read the same `modelModeProvider`. The Worker already passes streaming bodies through (Task 1), so no proxy change is expected.

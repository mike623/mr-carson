import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_capability.dart';
import 'gemma_service.dart';
import 'model_mode.dart';

/// Narrow seam the receipt pipeline depends on: given the extraction prompt and
/// the receipt image, return the model's raw text response.
///
/// Two backends implement it:
///  - [GemmaOcrEngine]  — the on-device flutter_gemma vision model (production).
///  - [OllamaOcrEngine] — a local Ollama server (dev), so the full OCR + parse +
///    retry flow can be exercised on the simulator/desktop where the on-device
///    GPU backend isn't available. Select it at build time:
///      --dart-define=OCR_BACKEND=ollama
///      --dart-define=OLLAMA_BASE_URL=http://localhost:11434   (default)
///      --dart-define=OLLAMA_MODEL=gemma3                       (vision-capable)
abstract class ReceiptOcrEngine {
  Future<String> readReceipt({
    required String prompt,
    required Uint8List imageBytes,
  });
}

/// Production backend — on-device Gemma vision session via [GemmaService].
class GemmaOcrEngine implements ReceiptOcrEngine {
  GemmaOcrEngine(this._gemma);

  final GemmaService _gemma;

  @override
  Future<String> readReceipt({
    required String prompt,
    required Uint8List imageBytes,
  }) async {
    final session = await _gemma.createVisionSession();
    try {
      await session.addQueryChunk(
        Message.withImage(text: prompt, imageBytes: imageBytes, isUser: true),
      );
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }
}

/// Dev backend — POSTs the image to a local Ollama vision model. Uses dart:io's
/// HttpClient (no extra dependency).
class OllamaOcrEngine implements ReceiptOcrEngine {
  OllamaOcrEngine({required this.baseUrl, required this.model});

  final String baseUrl;
  final String model;

  @override
  Future<String> readReceipt({
    required String prompt,
    required Uint8List imageBytes,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/api/generate'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': model,
        'prompt': prompt,
        'images': [base64Encode(imageBytes)],
        'stream': false,
        'format': 'json',
      })));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw HttpException('Ollama ${resp.statusCode}: $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return (decoded['response'] as String?) ?? '';
    } finally {
      client.close();
    }
  }
}

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
  defaultValue: 'google/gemma-4-26b-a4b-it',
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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/core/message.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gemma_service.dart';

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

const String _ocrBackend =
    String.fromEnvironment('OCR_BACKEND', defaultValue: 'gemma');
const String _ollamaBaseUrl = String.fromEnvironment(
  'OLLAMA_BASE_URL',
  defaultValue: 'http://localhost:11434',
);
const String _ollamaModel =
    String.fromEnvironment('OLLAMA_MODEL', defaultValue: 'gemma3');

/// Picks the OCR backend from build-time config; defaults to on-device Gemma.
final receiptOcrEngineProvider = Provider<ReceiptOcrEngine>((ref) {
  if (_ocrBackend == 'ollama') {
    return OllamaOcrEngine(baseUrl: _ollamaBaseUrl, model: _ollamaModel);
  }
  return GemmaOcrEngine(ref.watch(gemmaServiceProvider));
});

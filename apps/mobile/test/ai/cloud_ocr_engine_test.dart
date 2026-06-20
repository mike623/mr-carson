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
      model: 'google/gemini-2.0-flash-001',
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
    expect(capturedBody['model'], 'google/gemini-2.0-flash-001');
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

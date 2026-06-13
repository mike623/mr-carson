import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart';
import 'package:flutter_gemma/core/chat.dart';
import 'package:flutter_gemma/core/model.dart';
import 'package:flutter_gemma/pigeon.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// TODO: point at self-hosted Gemma 3n .litertlm
const String kDefaultModelUrl = 'https://example.com/gemma-3n.litertlm';

/// Lifecycle state of the on-device Gemma model.
enum GemmaState {
  /// Model file has not been downloaded yet.
  notDownloaded,

  /// Model is currently being downloaded.
  downloading,

  /// Model file is present and is being loaded into the inference engine.
  loading,

  /// Model is loaded and ready for inference.
  ready,

  /// An unrecoverable error occurred; check [GemmaService.lastError].
  error,
}

/// Singleton service that manages the on-device Gemma 3n model lifecycle.
///
/// Typical call sequence:
/// 1. Call [downloadModel] if the model is not yet on disk.
/// 2. Call [loadModel] to load the model into the inference engine (expensive —
///    keep the service alive for the app's lifetime).
/// 3. Downstream services call [createVisionSession] or [createChat] as needed.
/// 4. Call [dispose] when the app is terminating.
class GemmaService {
  GemmaService();

  // --- state ----------------------------------------------------------------

  final ValueNotifier<GemmaState> _stateNotifier =
      ValueNotifier(GemmaState.notDownloaded);

  /// Read-only listenable — UI layers can listen for lifecycle transitions
  /// without being able to mutate state directly.
  ValueListenable<GemmaState> get stateListenable => _stateNotifier;

  /// Current lifecycle state (convenience getter).
  GemmaState get state => _stateNotifier.value;

  /// The last error message, populated when [state] == [GemmaState.error].
  String? lastError;

  // Private handle to the loaded model.
  InferenceModel? _model;

  // Convenience accessor to the platform singleton.
  FlutterGemmaPlugin get _plugin => FlutterGemmaPlugin.instance;

  // --- download -------------------------------------------------------------

  /// Downloads and installs the model from [url].
  ///
  /// Emits download progress as integers 0–100 on the returned [Stream].
  /// The stream closes when installation is complete. After a successful
  /// download [state] returns to [GemmaState.notDownloaded] (ready to call
  /// [loadModel]).
  ///
  /// Defaults to [kDefaultModelUrl] if [url] is omitted.
  Stream<int> downloadModel([String? url]) async* {
    final targetUrl = url ?? kDefaultModelUrl;
    _stateNotifier.value = GemmaState.downloading;
    lastError = null;

    try {
      yield* _plugin.modelManager
          .downloadModelFromNetworkWithProgress(targetUrl);
      _stateNotifier.value = GemmaState.notDownloaded;
    } catch (e) {
      lastError = e.toString();
      _stateNotifier.value = GemmaState.error;
      rethrow;
    }
  }

  // --- load -----------------------------------------------------------------

  /// Loads the model into the inference engine.
  ///
  /// This is expensive (seconds) and should be called once per app session.
  /// After this completes successfully, [state] transitions to
  /// [GemmaState.ready].
  ///
  /// Used by `ReceiptPipelineService` (receipt_pipeline.dart) and
  /// `ChatService` (chat_service.dart) — both services wait for
  /// [state] == [GemmaState.ready] before calling [createVisionSession] or
  /// [createChat].
  Future<void> loadModel() async {
    _stateNotifier.value = GemmaState.loading;
    lastError = null;
    try {
      _model = await _plugin.createModel(
        modelType: ModelType.gemmaIt,
        preferredBackend: PreferredBackend.gpu,
        maxTokens: 4096,
        supportImage: true,
        maxNumImages: 1,
      );
      _stateNotifier.value = GemmaState.ready;
    } catch (e) {
      lastError = e.toString();
      _stateNotifier.value = GemmaState.error;
      rethrow;
    }
  }

  // --- session factories ----------------------------------------------------

  /// Creates a new vision-capable inference session.
  ///
  /// Used by `ReceiptPipelineService` (receipt_pipeline.dart) to extract
  /// structured data from receipt images. The caller is responsible for
  /// closing the returned session via `session.close()`.
  ///
  /// Throws [StateError] if the model is not loaded yet.
  Future<InferenceModelSession> createVisionSession() async {
    _assertReady();
    return _model!.createSession(
      temperature: 0.1,
      topK: 1,
      enableVisionModality: true,
    );
  }

  /// Creates a new chat object for multi-turn text conversation.
  ///
  /// Used by `ChatService` (chat_service.dart) for the butler persona chat.
  /// The caller is responsible for closing the underlying session when the
  /// conversation ends — call `chat.session.close()` to release the native
  /// inference handle.
  ///
  /// Throws [StateError] if the model is not loaded yet.
  Future<InferenceChat> createChat() async {
    _assertReady();
    return _model!.createChat(
      temperature: 0.8,
      topK: 40,
      supportImage: false,
    );
  }

  // --- cleanup --------------------------------------------------------------

  /// Releases the loaded model and resets state.
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
    _stateNotifier.value = GemmaState.notDownloaded;
    _stateNotifier.dispose();
  }

  // --- internal -------------------------------------------------------------

  void _assertReady() {
    if (_model == null || state != GemmaState.ready) {
      throw StateError(
        'GemmaService: model is not loaded. '
        'Call loadModel() and wait for state == GemmaState.ready.',
      );
    }
  }
}

/// Riverpod provider for [GemmaService].
///
/// Use `ref.read(gemmaServiceProvider)` to access the singleton service.
/// The provider registers [GemmaService.dispose] so the native InferenceModel
/// handle is released when the provider scope is torn down.
final gemmaServiceProvider = Provider<GemmaService>((ref) {
  final svc = GemmaService();
  ref.onDispose(svc.dispose);
  return svc;
});

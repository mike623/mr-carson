import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Self-hosted on Cloudflare R2 (public, tokenless). The object must be uploaded
// to the `mr-carson-models` bucket as `gemma-4-e2b.litertlm` (see
// apps/mobile/scripts/setup-r2.sh). NOTE: the Gemma 4 E2B `.litertlm` file does
// NOT exist in the bucket yet — uploading it is a separate infra task. Until it
// is uploaded this URL 404s and the onboarding ViewModel falls back to the mock
// download ramp.
const String kDefaultModelUrl =
    'https://pub-577b868d66aa4fd691ef6564611f0fc0.r2.dev/gemma-4-e2b.litertlm';

/// Whether the Gemma 4 E2B `.litertlm` file is actually hosted at
/// [kDefaultModelUrl]. Uploaded to the `mr-carson-models` R2 bucket on
/// 2026-06-14 (2.41 GiB; see apps/mobile/scripts/setup-r2.sh) — the public URL
/// serves the model (HTTP 200). When true the onboarding flow performs the real
/// download; flip back to false only if the object is removed.
const bool kModelHostedOnR2 = true;

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

/// Singleton service that manages the on-device Gemma 4 E2B model lifecycle.
///
/// Built on flutter_gemma 0.16.5's static API ([FlutterGemma.installModel] /
/// [FlutterGemma.getActiveModel]). The model is Gemma 4 E2B
/// ([ModelType.gemma4]), shipped as a `.litertlm` file
/// ([ModelFileType.litertlm]), which enables native function-calling tokens.
///
/// Typical call sequence:
/// 1. Call [downloadModel] if the model is not yet installed on disk. This both
///    downloads the file and registers it as the active model.
/// 2. Call [loadModel] to load the active model into the inference engine
///    (expensive — keep the service alive for the app's lifetime).
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

  // --- download -------------------------------------------------------------

  /// Downloads and installs the model from [url].
  ///
  /// Emits download progress as integers 0–100 on the returned [Stream].
  /// The stream closes when installation is complete. After a successful
  /// download [state] returns to [GemmaState.notDownloaded] (ready to call
  /// [loadModel]). On 0.16.5 the installed model is automatically registered as
  /// the active model, so [loadModel] can resolve it via
  /// [FlutterGemma.getActiveModel].
  ///
  /// Defaults to [kDefaultModelUrl] if [url] is omitted.
  Stream<int> downloadModel([String? url]) {
    final targetUrl = url ?? kDefaultModelUrl;
    _stateNotifier.value = GemmaState.downloading;
    lastError = null;

    // Bridge the synchronous withProgress(int) callback into a Stream<int>.
    // installModel().install() returns a single Future that completes when the
    // download finishes; the callback fires with incremental 0–100 values along
    // the way. We push each callback value onto the controller, then close it
    // (success) or forward the error (failure) when the Future settles.
    final controller = StreamController<int>();

    FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    )
        .fromNetwork(targetUrl)
        .withProgress((p) {
      if (!controller.isClosed) controller.add(p);
    }).install().then((_) {
      _stateNotifier.value = GemmaState.notDownloaded;
      if (!controller.isClosed) controller.close();
    }).catchError((Object e) {
      lastError = e.toString();
      _stateNotifier.value = GemmaState.error;
      if (!controller.isClosed) {
        controller.addError(e);
        controller.close();
      }
    });

    return controller.stream;
  }

  // --- load -----------------------------------------------------------------

  /// Loads the active model into the inference engine.
  ///
  /// This is expensive (seconds) and should be called once per app session.
  /// After this completes successfully, [state] transitions to
  /// [GemmaState.ready].
  ///
  /// Requires a previously installed model (via [downloadModel] or a bundled
  /// install) — [FlutterGemma.getActiveModel] throws [StateError] if no model
  /// has been installed yet.
  ///
  /// Used by `ReceiptPipelineService` (receipt_pipeline.dart) and
  /// `ChatService` (chat_service.dart) — both services wait for
  /// [state] == [GemmaState.ready] before calling [createVisionSession] or
  /// [createChat].
  Future<void> loadModel() async {
    _stateNotifier.value = GemmaState.loading;
    lastError = null;
    try {
      _model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        preferredBackend: PreferredBackend.gpu,
        supportImage: true,
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
  /// Pass [tools] (with [supportsFunctionCalls] = true) to enable Gemma 4's
  /// native function calling — the later chat_service rewrite uses this to let
  /// the butler call tools. [modelType] is always [ModelType.gemma4] so the
  /// native function-call tokens are formatted correctly.
  ///
  /// Throws [StateError] if the model is not loaded yet.
  Future<InferenceChat> createChat({
    List<Tool> tools = const [],
    bool supportsFunctionCalls = false,
    ToolChoice toolChoice = ToolChoice.auto,
  }) async {
    _assertReady();
    return _model!.createChat(
      temperature: 0.8,
      topK: 40,
      supportImage: false,
      tools: tools,
      supportsFunctionCalls: supportsFunctionCalls,
      toolChoice: toolChoice,
      modelType: ModelType.gemma4,
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

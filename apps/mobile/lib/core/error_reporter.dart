import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry DSN. A DSN is a publishable client identifier (safe to embed), so the
/// project DSN is baked in as the default — TestFlight/release builds report
/// without extra flags. Override per-build with:
///   flutter run --dart-define=SENTRY_DSN=https://...@sentry.io/123
/// Pass --dart-define=SENTRY_DSN= (empty) to disable reporting locally.
const String kSentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue:
      'https://1ffa33b5f62ba07e9a72800192e13bb5@o4511475545276416.ingest.de.sentry.io/4511598777598032',
);

/// Whether crash reporting is active for this build.
bool get sentryEnabled => kSentryDsn.isNotEmpty;

/// Reports a caught error to Sentry. No-op when [sentryEnabled] is false, so
/// call sites need no guard. [hint] tags the failure (e.g. 'receipt_ocr').
Future<void> reportError(
  Object error,
  StackTrace? stackTrace, {
  String? hint,
}) async {
  if (!sentryEnabled) return;
  await Sentry.captureException(
    error,
    stackTrace: stackTrace,
    withScope: hint == null ? null : (scope) => scope.setTag('area', hint),
  );
}

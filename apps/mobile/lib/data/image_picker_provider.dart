import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// Riverpod provider for the platform [ImagePicker].
///
/// Isolated behind a provider so tests can override it with a fake — a real
/// picker opens native UI and cannot run under `flutter test`.
final imagePickerProvider = Provider<ImagePicker>((ref) {
  return ImagePicker();
});

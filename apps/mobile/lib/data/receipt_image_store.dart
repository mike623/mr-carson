import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// A receipt image copied into the app's persistent storage.
///
/// [path] is the stable on-disk location (under `<documents>/receipts/`).
/// [imageHash] is the SHA-256 of the file bytes, used for dedup via
/// [AppDatabase.findByImageHash].
class StoredReceiptImage {
  const StoredReceiptImage({required this.path, required this.imageHash});

  final String path;
  final String imageHash;
}

/// Copies picked receipt images into durable app storage.
///
/// Image picker (camera/gallery) hands back temp-file paths that the OS may
/// reclaim at any time — they are NOT safe to persist as `source_file`. This
/// store copies the bytes into `<app documents>/receipts/<uuid>.<ext>` and
/// returns that stable path, alongside a SHA-256 hash of the bytes for dedup.
class ReceiptImageStore {
  ReceiptImageStore({Future<Directory> Function()? documentsDir})
      : _documentsDir = documentsDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDir;
  static const _uuid = Uuid();

  /// Returns (creating if needed) the `<documents>/receipts/` directory.
  Future<Directory> receiptsDir() async {
    final docs = await _documentsDir();
    final dir = Directory(p.join(docs.path, 'receipts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// SHA-256 hex digest of the bytes of the file at [path], or `null` if the
  /// file is missing/unreadable. This is the single source of truth for the
  /// receipt image-hash format: both [persist] (the up-front dedup pre-check)
  /// and the commit-time persistence in [ReceiptPipelineService] hash through
  /// here, so the recorded `expenses.image_hash` always matches the pre-check.
  Future<String?> hashFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (_) {
      return null;
    }
  }

  /// Copies the file at [sourcePath] into the receipts directory under a fresh
  /// UUID filename (preserving the original extension), computes its SHA-256
  /// hash, and returns the stable [StoredReceiptImage].
  Future<StoredReceiptImage> persist(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final hash = sha256.convert(bytes).toString();

    final dir = await receiptsDir();
    final ext = p.extension(sourcePath); // includes leading dot, may be ''
    final fileName = '${_uuid.v4()}$ext';
    final dest = File(p.join(dir.path, fileName));
    await dest.writeAsBytes(bytes, flush: true);

    return StoredReceiptImage(path: dest.path, imageHash: hash);
  }

  /// Deletes a stored receipt image (e.g. after the user discards it). Silently
  /// ignores a missing file.
  Future<void> cleanup(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Riverpod provider for [ReceiptImageStore].
final receiptImageStoreProvider = Provider<ReceiptImageStore>((ref) {
  return ReceiptImageStore();
});

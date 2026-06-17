import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Stores receipt image files in a stable on-device location.
///
/// Picker temp paths are ephemeral — this service copies them into
/// `<app documents>/receipts/` under a UUID name so the path persists
/// across restarts. No image bytes are written to the database.
class ReceiptImageStore {
  const ReceiptImageStore();

  /// Copies the file at [sourcePath] into the receipts directory.
  ///
  /// Returns a [ReceiptImageCopy] containing the stable [path] and
  /// the sha256 [imageHash] of the file bytes.
  Future<ReceiptImageCopy> copyReceipt(String sourcePath) async {
    final dir = await _receiptsDir();
    final ext = p.extension(sourcePath); // e.g. ".jpg"
    final destName = '${_uuid.v4()}$ext';
    final destPath = p.join(dir.path, destName);

    final srcFile = File(sourcePath);
    await srcFile.copy(destPath);

    final bytes = await File(destPath).readAsBytes();
    final hash = sha256.convert(bytes).toString();

    return ReceiptImageCopy(path: destPath, imageHash: hash);
  }

  /// Deletes [filePath] if it exists inside the receipts directory.
  /// Silent if the file is missing.
  Future<void> deleteReceipt(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Returns (creating if needed) the receipts directory.
  Future<Directory> get receiptsDirectory => _receiptsDir();

  Future<Directory> _receiptsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'receipts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

/// The result of [ReceiptImageStore.copyReceipt].
class ReceiptImageCopy {
  const ReceiptImageCopy({required this.path, required this.imageHash});

  /// Stable on-device file path.
  final String path;

  /// SHA-256 hex digest of the file bytes.
  final String imageHash;
}

/// Riverpod provider for [ReceiptImageStore].
final receiptImageStoreProvider =
    Provider<ReceiptImageStore>((_) => const ReceiptImageStore());

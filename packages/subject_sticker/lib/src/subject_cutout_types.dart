import 'dart:typed_data';

/// Result of a subject-cutout attempt.
class CutoutResult {
  const CutoutResult({this.png, this.error, this.elapsedMs});

  /// Transparent PNG of the extracted subject(s), or null on failure.
  final Uint8List? png;

  /// Human-readable failure reason (platform error message, etc.).
  final String? error;

  /// Wall-clock time of the segmentation call, in milliseconds.
  final int? elapsedMs;

  bool get ok => png != null;
}

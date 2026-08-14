import 'dart:io';

import 'package:flutter/services.dart';

import 'subject_cutout_types.dart';

const MethodChannel _channel = MethodChannel('subject_sticker');

/// Android: ML Kit Subject Segmentation via Play Services (requires minSdk 24).
/// iOS: Vision foreground instance mask — requires iOS 17+ at runtime; older
/// versions report unsupported so callers fall back gracefully.
bool get subjectCutoutSupported {
  if (Platform.isAndroid) return true;
  if (Platform.isIOS) return _iosMajorVersion >= 17;
  return false;
}

/// First integer of e.g. "Version 17.2 (Build 21C62)".
int get _iosMajorVersion {
  final match = RegExp(r'(\d+)').firstMatch(Platform.operatingSystemVersion);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// Runs on-device subject segmentation on the image at [filePath] and returns
/// the foreground as a transparent PNG.
///
/// Notes for integrators:
/// - Android requires `minSdk 24`. Add to AndroidManifest so Play installs
///   download the model up front:
///   `<meta-data android:name="com.google.mlkit.vision.DEPENDENCIES"
///               android:value="subject_segment" />`
///   Sideloaded builds download the model on first call instead — that first
///   call fails with a "waiting for the module to be downloaded" error until
///   Play Services finishes (~1–2 min).
/// - iOS needs no setup; the Vision model ships with the OS (17+).
Future<CutoutResult> trySubjectCutout(String filePath) async {
  if (!subjectCutoutSupported) {
    return const CutoutResult(error: 'unsupported platform');
  }
  final sw = Stopwatch()..start();
  try {
    final png = await _channel.invokeMethod<Uint8List>(
      'cutout',
      <String, Object>{'path': filePath},
    );
    if (png == null) {
      return CutoutResult(
        error: 'no foreground returned',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
    return CutoutResult(png: png, elapsedMs: sw.elapsedMilliseconds);
  } on PlatformException catch (e) {
    return CutoutResult(
      error: e.message ?? e.code,
      elapsedMs: sw.elapsedMilliseconds,
    );
  } catch (e) {
    return CutoutResult(error: '$e', elapsedMs: sw.elapsedMilliseconds);
  }
}

/// Same as [trySubjectCutout] but takes encoded image bytes (JPEG/PNG).
///
/// Both platforms take a file path (ML Kit only accepts one for encoded
/// images; Vision reads the file the same way), so the bytes are written to a
/// temp file first and removed afterwards. Use this when the image only
/// exists in memory (e.g. rotated/re-encoded after picking). On mobile,
/// `Directory.systemTemp` resolves to the app cache dir.
Future<CutoutResult> trySubjectCutoutBytes(Uint8List bytes) async {
  if (!subjectCutoutSupported) {
    return const CutoutResult(error: 'unsupported platform');
  }
  File? tmp;
  try {
    tmp = File(
      '${Directory.systemTemp.path}/subject_sticker_'
      '${DateTime.now().microsecondsSinceEpoch}.img',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    return await trySubjectCutout(tmp.path);
  } catch (e) {
    return CutoutResult(error: '$e');
  } finally {
    try {
      await tmp?.delete();
    } catch (_) {}
  }
}

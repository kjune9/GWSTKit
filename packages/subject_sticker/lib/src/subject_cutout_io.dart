import 'dart:io';

import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';

import 'subject_cutout_types.dart';

/// Android-only for now (ML Kit Subject Segmentation is Android-only in beta).
/// iOS is planned via VisionKit subject lifting.
bool get subjectCutoutSupported => Platform.isAndroid;

/// Runs on-device subject segmentation on the image at [filePath] and returns
/// the foreground as a transparent PNG.
///
/// Notes for integrators:
/// - Requires `minSdk 24` on Android.
/// - Add to AndroidManifest so Play installs download the model up front:
///   `<meta-data android:name="com.google.mlkit.vision.DEPENDENCIES"
///               android:value="subject_segment" />`
///   Sideloaded builds download the model on first call instead — that first
///   call fails with a "waiting for the module to be downloaded" error until
///   Play Services finishes (~1–2 min).
Future<CutoutResult> trySubjectCutout(String filePath) async {
  if (!subjectCutoutSupported) {
    return const CutoutResult(error: 'unsupported platform');
  }
  final sw = Stopwatch()..start();
  final segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundBitmap: true,
      enableForegroundConfidenceMask: false,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );
  try {
    final result =
        await segmenter.processImage(InputImage.fromFilePath(filePath));
    final png = result.foregroundBitmap;
    if (png == null) {
      return CutoutResult(
        error: 'no foreground returned',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }
    return CutoutResult(png: png, elapsedMs: sw.elapsedMilliseconds);
  } catch (e) {
    return CutoutResult(error: '$e', elapsedMs: sw.elapsedMilliseconds);
  } finally {
    segmenter.close();
  }
}

import 'dart:typed_data';

import 'subject_cutout_types.dart';

/// Web/desktop stub — subject segmentation is not available here.
bool get subjectCutoutSupported => false;

Future<CutoutResult> trySubjectCutout(String filePath) async =>
    const CutoutResult(error: 'unsupported platform');

Future<CutoutResult> trySubjectCutoutBytes(Uint8List bytes) async =>
    const CutoutResult(error: 'unsupported platform');

/// On-device subject cutout + sticker-style border rendering.
///
/// Two independent layers:
/// - [trySubjectCutout] (`subject_cutout.dart`) — platform-specific subject
///   segmentation (Android ML Kit today; stub elsewhere).
/// - [stickerize] (`stickerize.dart`) — pure-Dart post-processing that turns
///   a transparent cutout PNG into a die-cut sticker (margin + contour line).
///
/// Plus cleanup helpers:
/// - [eraseComponentAt] (`erase_component.dart`) — tap-to-delete stray blobs
///   the segmentation dragged in.
/// - [restoreRegionAt] (`restore_component.dart`) — tap-to-bring-back parts
///   the segmentation cut away (e.g. an empty plate rim), refilled from the
///   original photo with a color-similarity flood.
/// - [applyStroke] (`stroke_component.dart`) — brush strokes for precision:
///   restore or erase exactly what the finger covered, no color rules.
library;

export 'src/erase_component.dart';
export 'src/restore_component.dart';
export 'src/stickerize.dart';
export 'src/stroke_component.dart';
export 'src/subject_cutout.dart';

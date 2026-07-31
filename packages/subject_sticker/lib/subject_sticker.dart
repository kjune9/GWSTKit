/// On-device subject cutout + sticker-style border rendering.
///
/// Two independent layers:
/// - [trySubjectCutout] (`subject_cutout.dart`) — platform-specific subject
///   segmentation (Android ML Kit today; stub elsewhere).
/// - [stickerize] (`stickerize.dart`) — pure-Dart post-processing that turns
///   a transparent cutout PNG into a die-cut sticker (margin + contour line).
///
/// Plus a cleanup helper: [eraseComponentAt] (`erase_component.dart`) —
/// tap-to-delete stray blobs the segmentation dragged in.
library;

export 'src/erase_component.dart';
export 'src/stickerize.dart';
export 'src/subject_cutout.dart';

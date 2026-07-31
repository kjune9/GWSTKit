/// On-device subject cutout + sticker-style border rendering.
///
/// Two independent layers:
/// - [trySubjectCutout] (`subject_cutout.dart`) — platform-specific subject
///   segmentation (Android ML Kit today; stub elsewhere).
/// - [stickerize] (`stickerize.dart`) — pure-Dart post-processing that turns
///   a transparent cutout PNG into a die-cut sticker (margin + contour line).
library;

export 'src/stickerize.dart';
export 'src/subject_cutout.dart';

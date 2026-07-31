# subject_sticker

On-device **subject cutout** (ML Kit Subject Segmentation) plus pure-Dart
**sticker-style border rendering** — turn any photo into a die-cut sticker:
white (or tinted) margin, colored contour line, stitch dashes, rounded
finishing everywhere (including subjects clipped by the photo edge).

Extracted from [JipCook](https://jipcook.pages.dev), where it turns family
cooking photos into stickers. Pre-1.0: the API may still move.

## Usage

```dart
import 'package:flutter/foundation.dart' show compute;
import 'package:subject_sticker/subject_sticker.dart';

// 1) Cut the subject out of a photo file (Android, on-device, free).
final cut = await trySubjectCutout(photo.path);
if (!cut.ok) {
  // cut.error explains why (unsupported platform, model still downloading…)
  return;
}

// 2) Stickerize the transparent PNG (run in an isolate — it's CPU work).
final sticker = await compute(
  stickerize,
  StickerizeRequest(
    cut.png!,
    lineStyle: StickerLineStyle.dashed, // none | solid | dashed
    lineArgb: 0xFFE8552F,               // contour line color
    tintMargin: false,                  // pale tint of the line color as margin
  ),
);
// `sticker` is a transparent PNG, ready to display or upload.
```

Typical timings on a 2025 mid/high-end phone, 1600px photo:
segmentation ~0.9 s, stickerize ~1 s.

## Android setup

- `minSdk 24` (ML Kit Subject Segmentation requirement).
- Recommended, so Play installs download the segmentation model up front:

```xml
<meta-data
    android:name="com.google.mlkit.vision.DEPENDENCIES"
    android:value="subject_segment" />
```

Sideloaded builds fetch the model on first use instead; that first call fails
with a "waiting for the module to be downloaded" error until Play Services
finishes (usually 1–2 minutes).

## Platform support

| Platform | Cutout | Stickerize |
|----------|--------|------------|
| Android  | ✅ ML Kit (on-device) | ✅ |
| iOS      | 🔜 planned (VisionKit subject lifting) | ✅ |
| Web/desktop | ❌ stub (`subjectCutoutSupported == false`) | ✅ |

`stickerize` is pure Dart (`image` package only) — it runs anywhere Dart runs,
so you can also stickerize server-side or from a CLI.

## How it works (short version)

1. **Distance field** from the subject's alpha mask — chamfer 5-7-11, two
   passes, O(n). Close enough to Euclidean that corners round like circles.
2. **Closing pass** — dilate by the full border width, then measure back
   inward. Concave valleys (two chopsticks meeting) finish round instead of
   as sharp V notches; subjects clipped by the photo edge get wrapped too.
3. **Bands** — margin / line / margin by distance, feathered edges.
4. **Stitch dashes** — the line's centerline contour is traced
   (Moore neighborhood), then round-capped dashes are stamped by arc length,
   so stitches stay uniform on any contour direction.

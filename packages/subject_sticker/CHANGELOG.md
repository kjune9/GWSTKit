# Changelog

## 0.1.0

- **iOS subject cutout** — `trySubjectCutout` now works on iOS 17+ via the
  Vision foreground instance mask (`VNGenerateForegroundInstanceMaskRequest`).
  No setup needed; the model ships with the OS. Older iOS versions report
  `subjectCutoutSupported == false` so existing fallbacks keep working.
- **Converted to a platform plugin** — the package now carries its own native
  code (Kotlin on Android, Swift on iOS, method channel `subject_sticker`)
  and no longer depends on the `google_mlkit_*` Dart plugins. Android still
  uses ML Kit Subject Segmentation via Play Services under the hood; behavior
  and the public Dart API are unchanged.
  - Why: the ML Kit Dart plugin's iOS side is a stub that cannot cut out
    subjects, yet it dragged the full MLKitVision framework into iOS builds —
    forcing a 15.5 minimum deployment target and (having no arm64 simulator
    slice) breaking iOS simulator builds on Apple Silicon Macs. All three go
    away with this release: iOS deployment target can be as low as 13.0.
- iOS plugin ships in the dual CocoaPods + Swift Package Manager layout.

## 0.0.4

- `restoreRegionAt` — tap-to-bring-back a region the segmentation cut away
  (the inverse of `eraseComponentAt`). Copies pixels back from the original
  photo via a seed-color flood fill: similar-colored surfaces (an empty plate
  rim) return in one tap, and the fill stops on its own at color boundaries.
  Handles EXIF orientation and resolution mismatches between the original
  and the cutout, and softens the restored edge by one pixel.
  Transparent pockets fully enclosed by the restored region (specular
  glints, embossed-pattern highlights) are filled regardless of color —
  without this a glossy surface comes back perforated. Open surroundings
  always touch the region's outside and are never filled.
- `applyStroke` — brush strokes as the precision counterpart to the tap
  tools: restore (copy back from the original) or erase exactly the pixels
  under a finger-drawn polyline, no color rules. The tap flood cannot reach
  thin edge bands where colors shift, and the blob erase cannot trim a
  piece fused to the subject — the brush covers both. Soft rim on the
  stroke boundary.

## 0.0.3

- `eraseComponentAt` — tap-to-delete a stray blob from a cutout PNG:
  flood-fills the 8-connected opaque component under (or near) the tap and
  clears it to transparent. For cleaning up bits the segmentation dragged in.

## 0.0.2

- `trySubjectCutoutBytes` — cutout from in-memory encoded image bytes
  (writes a temp file for ML Kit, cleans up afterwards). Useful when the
  image was re-encoded after picking (e.g. rotation).

## 0.0.1

- Initial extraction from JipCook.
- `trySubjectCutout` — on-device subject segmentation (Android, ML Kit beta);
  stub on unsupported platforms (web/desktop return "unsupported").
- `stickerize` — sticker post-processing on the transparent cutout PNG:
  - white (or tinted) margin following the silhouette,
  - optional colored contour line centered in the margin (solid / dashed),
  - stitch-style dashes with round caps traced along the contour arc length,
  - closing pass so concave valleys and photo-edge cuts finish with round corners,
  - canvas extended past the photo edge so clipped subjects still get a full border.

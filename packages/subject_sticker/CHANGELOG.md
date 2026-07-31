# Changelog

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

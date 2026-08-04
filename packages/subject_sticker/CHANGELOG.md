# Changelog

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

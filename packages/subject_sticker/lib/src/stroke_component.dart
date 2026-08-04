import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Request bundle for [applyStroke] — a single object so it can be passed
/// straight to Flutter's `compute()`.
class StrokeRequest {
  const StrokeRequest(
    this.cutoutPng, {
    this.originalBytes,
    required this.points,
    required this.radius,
    this.erase = false,
  });

  /// Transparent cutout PNG being retouched.
  final Uint8List cutoutPng;

  /// The photo the cutout was made from. Required for restore strokes
  /// (pixels are copied back from here); unused for erase strokes.
  final Uint8List? originalBytes;

  /// Stroke polyline in cutout pixels, flattened `[x1, y1, x2, y2, ...]`.
  /// A single point paints one disc.
  final List<double> points;

  /// Brush radius in cutout pixels.
  final double radius;

  /// false = restore brush (bring pixels back from the original),
  /// true = erase brush (clear pixels to transparent).
  final bool erase;
}

/// Paints a brush stroke on the cutout — the precision counterpart to the
/// tap tools ([eraseComponentAt] / `restoreRegionAt`).
///
/// The tap tools are smart but color-bound: a flood restore recovers a
/// surface but cannot reach the thin edge band where colors shift, and a
/// blob erase cannot trim a piece that is fused to the subject. A brush is
/// dumb on purpose: **exactly what the finger covered**, no color rules.
/// Zooming the preview makes the fixed-size brush finer on screen, so zoom
/// is the precision dial.
///
/// Restore strokes copy RGB from the original photo (EXIF orientation baked,
/// resized to the cutout if needed) into transparent pixels under the
/// stroke. Erase strokes clear opaque pixels under the stroke. Either way
/// the stroke's outer rim gets a soft edge so it sits next to the
/// segmentation's feathered edges without a razor line.
///
/// Returns the updated PNG, or `null` when the stroke changed nothing
/// (restored where everything was already opaque / erased where everything
/// was already transparent) or the bytes fail to decode. Run inside
/// `compute()`.
Uint8List? applyStroke(StrokeRequest req) {
  if (req.points.length < 2 || req.points.length.isOdd) return null;
  final im = img.decodePng(req.cutoutPng);
  if (im == null) return null;
  final w = im.width, h = im.height;

  img.Image? orig;
  if (!req.erase) {
    if (req.originalBytes == null) return null;
    orig = img.decodeImage(req.originalBytes!);
    if (orig == null) return null;
    orig = img.bakeOrientation(orig);
    if (orig.width != w || orig.height != h) {
      orig = img.copyResize(
        orig,
        width: w,
        height: h,
        interpolation: img.Interpolation.linear,
      );
    }
  }

  // 1) Coverage mask — stamp discs along each segment at half-radius steps
  //    so the stroke is solid, then a soft rim can be derived from it.
  final r = math.max(1.0, req.radius);
  final mask = Uint8List(w * h);
  void stamp(double cx, double cy) {
    final x0 = math.max(0, (cx - r).floor());
    final x1 = math.min(w - 1, (cx + r).ceil());
    final y0 = math.max(0, (cy - r).floor());
    final y1 = math.min(h - 1, (cy + r).ceil());
    final r2 = r * r;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx, dy = y - cy;
        if (dx * dx + dy * dy <= r2) mask[y * w + x] = 1;
      }
    }
  }

  final pts = req.points;
  stamp(pts[0], pts[1]);
  for (var i = 2; i + 1 < pts.length; i += 2) {
    final ax = pts[i - 2], ay = pts[i - 1], bx = pts[i], by = pts[i + 1];
    final d = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final steps = math.max(1, (d / (r / 2)).ceil());
    for (var s = 1; s <= steps; s++) {
      stamp(ax + (bx - ax) * s / steps, ay + (by - ay) * s / steps);
    }
  }

  // 2) Apply. Rim pixels (mask boundary) get a softer alpha.
  bool masked(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] == 1;
  bool rim(int x, int y) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        if (mask[ny * w + nx] == 0) return true;
      }
    }
    return false;
  }

  var changed = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!masked(x, y)) continue;
      final p = im.getPixel(x, y);
      if (req.erase) {
        if (p.a <= 8) continue;
        // Rim keeps a whisper of alpha so the cut edge isn't razor-hard.
        if (rim(x, y)) {
          im.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 60);
        } else {
          im.setPixelRgba(x, y, 0, 0, 0, 0);
        }
        changed++;
      } else {
        if (p.a > 8) continue; // already there — brush only fills gaps
        final o = orig!.getPixel(x, y);
        im.setPixelRgba(
          x,
          y,
          o.r.toInt(),
          o.g.toInt(),
          o.b.toInt(),
          rim(x, y) ? 170 : 255,
        );
        changed++;
      }
    }
  }
  if (changed == 0) return null;
  return Uint8List.fromList(img.encodePng(im));
}

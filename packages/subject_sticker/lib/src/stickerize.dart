import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Contour line style drawn in the middle of the sticker margin.
enum StickerLineStyle { none, solid, dashed }

/// Request bundle for [stickerize] — a single object so it can be passed
/// straight to Flutter's `compute()` (which takes exactly one argument).
class StickerizeRequest {
  const StickerizeRequest(
    this.cutoutPng, {
    this.lineStyle = StickerLineStyle.none,
    this.lineArgb = 0xFFE8552F,
    this.tintMargin = false,
  });

  /// Transparent PNG of the subject (e.g. from `trySubjectCutout`).
  final Uint8List cutoutPng;

  /// Style of the colored contour line.
  final StickerLineStyle lineStyle;

  /// Contour line color as 0xAARRGGBB.
  final int lineArgb;

  /// When true, the margin is a pale tint of [lineArgb] instead of white.
  final bool tintMargin;
}

/// Turns a transparent cutout PNG into a die-cut sticker.
///
/// Pure Dart (`image` package) — run it inside an isolate (`compute()`)
/// because encoding a large PNG is slow on the UI thread.
///
/// Structure, inside → out:
/// original → margin → optional colored contour line → margin → soft fade.
/// The line sits centered in the margin band (equal width on both sides).
/// Subjects clipped by the photo edge still get a full border: the canvas is
/// extended past the photo bounds and the cut edge is wrapped like any other.
///
/// How it works:
/// 1. Chamfer distance transform (5-7-11, two passes, O(n)) from the subject
///    alpha mask. 5-7-11 (with knight moves) stays within ~2% of Euclidean,
///    so convex corners round like circles instead of octagon facets.
/// 2. A closing pass: dilate the subject by the full border width, then
///    measure distance back inward from the outside. Using that inverted
///    distance rounds concave valleys (e.g. where two chopsticks meet) that
///    a plain outward distance would leave as sharp V notches.
/// 3. Composite by distance band: margin / line / margin / fade, then
///    alpha-blend the original on top.
/// 4. Dashed lines are stamped separately: the contour at the line's center
///    is traced with Moore neighborhood tracing, and round-capped dashes are
///    stamped by arc length — uniform stitches regardless of contour
///    direction (angle- or grid-based dashing stretches or fragments).
Uint8List stickerize(StickerizeRequest req) {
  var im = img.decodePng(req.cutoutPng);
  if (im == null) throw ArgumentError('not a PNG');

  // Speed/size cap. 1600px matches a typical upload pipeline.
  const maxSide = 1600;
  final side = math.max(im.width, im.height);
  if (side > maxSide) {
    im = img.copyResize(
      im,
      width: im.width >= im.height ? maxSide : null,
      height: im.height > im.width ? maxSide : null,
      interpolation: img.Interpolation.linear,
    );
  }

  final w = im.width, h = im.height;
  // Margin width in px, proportional to image size.
  final margin = (math.max(w, h) * 0.026).clamp(9.0, 42.0);
  final hasLine = req.lineStyle != StickerLineStyle.none;
  // Line width — proportional to the margin but never chunky.
  final lineW = hasLine ? (margin * 0.42).clamp(4.0, 14.0) : 0.0;
  // Outer margin — same width as the inner one so the line looks centered.
  final outerMargin = hasLine ? margin : 0.0;

  // 1) Subject bounding box + alpha grid.
  int minX = w, minY = h, maxX = -1, maxY = -1;
  int mass = 0;
  final alpha = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = im.getPixel(x, y).a.toInt();
      alpha[y * w + x] = a;
      if (a > 8) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      if (a > 127) mass++;
    }
  }
  if (maxX < 0 || mass == 0) throw StateError('empty cutout');
  // Extend the canvas past the photo bounds (no clamping) so subjects cut off
  // by the photo edge get the full margin+line treatment along the cut.
  // Pixels outside the photo are treated as transparent.
  final pad = (margin + lineW + outerMargin).ceil() + 6;
  minX -= pad;
  minY -= pad;
  maxX += pad;
  maxY += pad;
  final cw = maxX - minX + 1, ch = maxY - minY + 1;

  // 2) Chamfer distance transform 5-7-11 (orthogonal 5, diagonal 7,
  //    knight 11 ≈ distance ×5).
  const inf = 1 << 29;
  final dist = Int32List(cw * ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final gx = x + minX, gy = y + minY;
      final inside = gx >= 0 && gy >= 0 && gx < w && gy < h &&
          alpha[gy * w + gx] > 127;
      dist[y * cw + x] = inside ? 0 : inf;
    }
  }
  int at(int x, int y) =>
      (x < 0 || y < 0 || x >= cw || y >= ch) ? inf : dist[y * cw + x];
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      var d = dist[y * cw + x];
      d = math.min(d, at(x - 1, y) + 5);
      d = math.min(d, at(x, y - 1) + 5);
      d = math.min(d, at(x - 1, y - 1) + 7);
      d = math.min(d, at(x + 1, y - 1) + 7);
      d = math.min(d, at(x - 2, y - 1) + 11);
      d = math.min(d, at(x - 1, y - 2) + 11);
      d = math.min(d, at(x + 1, y - 2) + 11);
      d = math.min(d, at(x + 2, y - 1) + 11);
      dist[y * cw + x] = d;
    }
  }
  for (var y = ch - 1; y >= 0; y--) {
    for (var x = cw - 1; x >= 0; x--) {
      var d = dist[y * cw + x];
      d = math.min(d, at(x + 1, y) + 5);
      d = math.min(d, at(x, y + 1) + 5);
      d = math.min(d, at(x + 1, y + 1) + 7);
      d = math.min(d, at(x - 1, y + 1) + 7);
      d = math.min(d, at(x + 2, y + 1) + 11);
      d = math.min(d, at(x + 1, y + 2) + 11);
      d = math.min(d, at(x - 1, y + 2) + 11);
      d = math.min(d, at(x - 2, y + 1) + 11);
      dist[y * cw + x] = d;
    }
  }

  final whiteEnd = margin;
  final lineEnd = whiteEnd + lineW;
  final outerEnd = lineEnd + outerMargin;
  const feather = 2.0; // outer edge fade, px
  const aa = 1.0; // line edge anti-alias, px

  // 3) Closing pass — with the outward distance alone, the borders of two
  //    nearby protrusions (chopsticks etc.) meet in a sharp V. Dilate the
  //    subject by rc, then measure distance back inward from the outside of
  //    that dilated shape; d' = rc - dist2 keeps convex corners round and
  //    fills concave valleys with a round finish.
  final rc = outerEnd + feather;
  final dist2 = Int32List(cw * ch);
  final rcCh = (rc * 5).round(); // chamfer units
  for (var i = 0; i < cw * ch; i++) {
    dist2[i] = dist[i] > rcCh ? 0 : inf; // outside the dilated shape = seed
  }
  int at2(int x, int y) =>
      (x < 0 || y < 0 || x >= cw || y >= ch) ? inf : dist2[y * cw + x];
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      var d = dist2[y * cw + x];
      d = math.min(d, at2(x - 1, y) + 5);
      d = math.min(d, at2(x, y - 1) + 5);
      d = math.min(d, at2(x - 1, y - 1) + 7);
      d = math.min(d, at2(x + 1, y - 1) + 7);
      d = math.min(d, at2(x - 2, y - 1) + 11);
      d = math.min(d, at2(x - 1, y - 2) + 11);
      d = math.min(d, at2(x + 1, y - 2) + 11);
      d = math.min(d, at2(x + 2, y - 1) + 11);
      dist2[y * cw + x] = d;
    }
  }
  for (var y = ch - 1; y >= 0; y--) {
    for (var x = cw - 1; x >= 0; x--) {
      var d = dist2[y * cw + x];
      d = math.min(d, at2(x + 1, y) + 5);
      d = math.min(d, at2(x, y + 1) + 5);
      d = math.min(d, at2(x + 1, y + 1) + 7);
      d = math.min(d, at2(x - 1, y + 1) + 7);
      d = math.min(d, at2(x + 2, y + 1) + 11);
      d = math.min(d, at2(x + 1, y + 2) + 11);
      d = math.min(d, at2(x - 1, y + 2) + 11);
      d = math.min(d, at2(x - 2, y + 1) + 11);
      dist2[y * cw + x] = d;
    }
  }

  // 4) Dash layer — trace the contour at the line's center and stamp
  //    round-capped dashes by arc length.
  Float32List? dashA;
  if (req.lineStyle == StickerLineStyle.dashed) {
    dashA = _dashLayer(
      dist2, cw, ch,
      rc: rc,
      mid: whiteEnd + lineW / 2,
      radius: lineW / 2,
      dashLen: lineW * 3.0,
      gapLen: lineW * 1.7,
    );
  }

  // 5) Composite by distance band (px):
  //    [0, whiteEnd] margin / (whiteEnd, lineEnd] line /
  //    (lineEnd, outerEnd] margin / fade.
  final lr = (req.lineArgb >> 16) & 0xFF;
  final lg = (req.lineArgb >> 8) & 0xFF;
  final lb = req.lineArgb & 0xFF;
  // Margin background — white by default, or a 14% tint of the line color.
  const tint = 0.14;
  final mr = req.tintMargin ? 255 + (lr - 255) * tint : 255.0;
  final mg = req.tintMargin ? 255 + (lg - 255) * tint : 255.0;
  final mb = req.tintMargin ? 255 + (lb - 255) * tint : 255.0;

  final out = img.Image(width: cw, height: ch, numChannels: 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final d = rc - dist2[y * cw + x] / 5.0; // closed distance in px
      final edge = hasLine ? outerEnd : whiteEnd;
      final wa = ((edge + feather - d) / feather).clamp(0.0, 1.0);
      final gx = x + minX, gy = y + minY;
      final inPhoto = gx >= 0 && gy >= 0 && gx < w && gy < h;
      final p = inPhoto ? im.getPixel(gx, gy) : null;
      final sa = p == null ? 0.0 : p.a / 255.0;
      final oa = sa + wa * (1 - sa);
      if (oa <= 0) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      var br = mr, bg = mg, bb = mb;
      var la = 0.0;
      if (dashA != null) {
        la = dashA[y * cw + x];
      } else if (hasLine && d > whiteEnd - aa && d < lineEnd + aa) {
        la = ((d - (whiteEnd - aa)) / aa).clamp(0.0, 1.0) *
            ((lineEnd + aa - d) / aa).clamp(0.0, 1.0);
      }
      if (la > 0) {
        br = mr + (lr - mr) * la;
        bg = mg + (lg - mg) * la;
        bb = mb + (lb - mb) * la;
      }
      // Original alpha-blended over the background. (p == null → sa == 0.)
      final r = ((p?.r ?? 0) * sa + br * wa * (1 - sa)) / oa;
      final g = ((p?.g ?? 0) * sa + bg * wa * (1 - sa)) / oa;
      final b = ((p?.b ?? 0) * sa + bb * wa * (1 - sa)) / oa;
      out.setPixelRgba(
        x, y, r.round(), g.round(), b.round(), (oa * 255).round(),
      );
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

/// Dash layer — walk the boundary of the contour at the line's center
/// (Moore neighborhood tracing), decide dash on/off by arc length, and stamp
/// filled circles of [radius] during "on" stretches (round caps, stitch look).
/// Disjoint subjects (several plates) each get their own loop.
/// Returns a canvas-sized line alpha (0–1).
Float32List _dashLayer(
  Int32List dist2,
  int cw,
  int ch, {
  required double rc,
  required double mid,
  required double radius,
  required double dashLen,
  required double gapLen,
}) {
  final layer = Float32List(cw * ch);
  // Mask of everything inside the line's centerline contour.
  final mask = Uint8List(cw * ch);
  for (var i = 0; i < cw * ch; i++) {
    if (rc - dist2[i] / 5.0 <= mid) mask[i] = 1;
  }
  bool inside(int x, int y) =>
      x >= 0 && y >= 0 && x < cw && y < ch && mask[y * cw + x] == 1;

  void stamp(int px, int py) {
    final r = radius;
    final ri = (r + 1).ceil();
    for (var yy = py - ri; yy <= py + ri; yy++) {
      for (var xx = px - ri; xx <= px + ri; xx++) {
        if (xx < 0 || yy < 0 || xx >= cw || yy >= ch) continue;
        final dd = math.sqrt(
          ((xx - px) * (xx - px) + (yy - py) * (yy - py)).toDouble(),
        );
        final a = (r + 0.5 - dd).clamp(0.0, 1.0);
        final i = yy * cw + xx;
        if (a > layer[i]) layer[i] = a;
      }
    }
  }

  // Eight directions, clockwise (screen coords, y down): E SE S SW W NW N NE.
  const ddx = [1, 1, 0, -1, -1, -1, 0, 1];
  const ddy = [0, 1, 1, 1, 0, -1, -1, -1];
  final visited = Uint8List(cw * ch);
  final period = dashLen + gapLen;

  for (var sy = 0; sy < ch; sy++) {
    for (var sx = 0; sx < cw; sx++) {
      final si = sy * cw + sx;
      // Start = a boundary pixel whose left neighbor is outside
      // (unvisited components only).
      if (mask[si] != 1 || visited[si] == 1 || inside(sx - 1, sy)) continue;
      var cx = sx, cy = sy;
      var prevDir = 6; // pretend we arrived heading north (left-edge start)
      var arc = 0.0;
      int? firstMove;
      final cap = 10 * (cw + ch); // safety bound
      for (var step = 0; step < cap; step++) {
        visited[cy * cw + cx] = 1;
        // Next boundary pixel — scan clockwise starting behind-left of the
        // previous heading.
        var found = -1;
        for (var k = 0; k < 8; k++) {
          final di = (prevDir + 6 + k) % 8;
          if (inside(cx + ddx[di], cy + ddy[di])) {
            found = di;
            break;
          }
        }
        if (found < 0) {
          // Isolated single-pixel component — one dot, done.
          if ((arc % period) < dashLen) stamp(cx, cy);
          break;
        }
        if (cx == sx && cy == sy) {
          if (firstMove == null) {
            firstMove = found;
          } else if (found == firstMove && step > 0) {
            break; // full loop (re-entered the start the same way)
          }
        }
        if ((arc % period) < dashLen) stamp(cx, cy);
        cx += ddx[found];
        cy += ddy[found];
        arc += (ddx[found].abs() + ddy[found].abs() == 2) ? 1.41421356 : 1.0;
        prevDir = found;
      }
    }
  }
  return layer;
}

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Request bundle for [restoreRegionAt] — a single object so it can be
/// passed straight to Flutter's `compute()`.
class RestoreRegionRequest {
  const RestoreRegionRequest(
    this.cutoutPng,
    this.originalBytes, {
    required this.x,
    required this.y,
    this.tolerance = 48,
  });

  /// Transparent cutout PNG (e.g. from `trySubjectCutout`, possibly already
  /// modified by `eraseComponentAt` / previous restores).
  final Uint8List cutoutPng;

  /// The photo the cutout was made from (any decodable format). Pixels are
  /// copied back from here. EXIF orientation is baked before use, and the
  /// image is resized to the cutout's dimensions if they differ.
  final Uint8List originalBytes;

  /// Tap position in cutout pixels.
  final int x;
  final int y;

  /// Max Euclidean RGB distance from the seed pixel's color for a pixel to
  /// join the restored region. Similar-colored surfaces (a plate face) come
  /// back in one tap; the fill stops on its own at color boundaries (plate
  /// edge against a wooden table). Differently-shaded parts of the same
  /// object may need another tap — by design, so one tap can't swallow the
  /// whole background.
  final int tolerance;
}

/// Restores a region the segmentation cut away, by copying pixels back from
/// the original photo. The inverse of `eraseComponentAt`.
///
/// Subject segmentation treats "empty" surfaces as background even when they
/// belong to the subject's vessel — the classic case is a plate rim with no
/// food on it, which gets cut off mid-plate. "Tap the missing part to bring
/// it back" fixes that without an eraser/brush UI.
///
/// How it works:
/// 1. Seed = the tapped pixel if it is transparent in the cutout, otherwise
///    the nearest transparent pixel within a small radius (~1.5% of the long
///    side, min 12 px) — mirroring `eraseComponentAt`'s forgiving tap.
/// 2. BFS flood fill (8-connected) over pixels that are still transparent in
///    the cutout AND whose color in the original is within [RestoreRegionRequest.tolerance]
///    of the seed's color. Each filled pixel gets the original's RGB with
///    full alpha.
/// 3. A 1-px soft edge: filled pixels touching unfilled transparency get a
///    slightly lower alpha so the new boundary doesn't look razor-cut next
///    to the segmentation's feathered edges.
///
/// Returns the updated PNG, or `null` when there is nothing to restore near
/// the tap (tapped the subject itself) or the bytes fail to decode. Run
/// inside `compute()` — decode + fill + re-encode is too slow for the UI
/// thread.
Uint8List? restoreRegionAt(RestoreRegionRequest req) {
  final im = img.decodePng(req.cutoutPng);
  if (im == null) return null;
  final w = im.width, h = im.height;

  var orig = img.decodeImage(req.originalBytes);
  if (orig == null) return null;
  // Photos straight from a camera carry EXIF rotation; the cutout is upright.
  orig = img.bakeOrientation(orig);
  if (orig.width != w || orig.height != h) {
    // Different resolution (or a pre-bake mismatch): map by resampling.
    orig = img.copyResize(
      orig,
      width: w,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }

  bool transparent(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && im.getPixel(x, y).a <= 8;

  // 1) Seed — tapped pixel, or the nearest transparent pixel within radius.
  var sx = req.x, sy = req.y;
  if (sx < 0 || sy < 0 || sx >= w || sy >= h) return null;
  if (!transparent(sx, sy)) {
    final radius = math.max(12, (math.max(w, h) * 0.015).round());
    var best = -1, bx = 0, by = 0;
    for (var y = math.max(0, sy - radius);
        y <= math.min(h - 1, sy + radius);
        y++) {
      for (var x = math.max(0, sx - radius);
          x <= math.min(w - 1, sx + radius);
          x++) {
        if (!transparent(x, y)) continue;
        final d = (x - sx) * (x - sx) + (y - sy) * (y - sy);
        if (d <= radius * radius && (best < 0 || d < best)) {
          best = d;
          bx = x;
          by = y;
        }
      }
    }
    if (best < 0) return null;
    sx = bx;
    sy = by;
  }

  final seed = orig.getPixel(sx, sy);
  final sr = seed.r.toInt(), sg = seed.g.toInt(), sb = seed.b.toInt();
  final tol2 = req.tolerance * req.tolerance;

  bool similar(int x, int y) {
    final p = orig!.getPixel(x, y);
    final dr = p.r.toInt() - sr, dg = p.g.toInt() - sg, db = p.b.toInt() - sb;
    return dr * dr + dg * dg + db * db <= tol2;
  }

  // 2) BFS flood fill — transparent in cutout + seed-similar in original.
  final filled = Uint8List(w * h); // doubles as the visited set
  final queue = Queue<int>()..add(sy * w + sx);
  filled[sy * w + sx] = 1;
  var filledCount = 1;
  var minX = sx, maxX = sx, minY = sy, maxY = sy;
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w, y = i ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (!transparent(nx, ny)) continue;
        final ni = ny * w + nx;
        if (filled[ni] == 1) continue;
        if (!similar(nx, ny)) continue;
        filled[ni] = 1;
        filledCount++;
        if (nx < minX) minX = nx;
        if (nx > maxX) maxX = nx;
        if (ny < minY) minY = ny;
        if (ny > maxY) maxY = ny;
        queue.add(ni);
      }
    }
  }

  // 2b) Enclosed-pocket pass. A glossy plate face is full of pixels the
  //     seed tolerance skips — specular glints, embossed-pattern highlights,
  //     shadow gradients — and skipping them leaves the restored face
  //     perforated with holes. Any transparent not-filled pocket that is
  //     fully enclosed by the restored region (cannot reach the region's
  //     outside) belongs to the same surface, so fill it regardless of
  //     color. Open areas (the table around the plate) always touch the
  //     outside and are never filled, so this cannot leak.
  //
  //     Method: flood the "transparent & not filled" pixels from the
  //     bounding box border inward — whatever that flood cannot reach is
  //     enclosed. A safety cap skips pockets larger than the flood itself
  //     (a pocket that big is scenery seen through a gap, not a glint).
  if (filledCount > 0) {
    minX = math.max(0, minX - 1);
    minY = math.max(0, minY - 1);
    maxX = math.min(w - 1, maxX + 1);
    maxY = math.min(h - 1, maxY + 1);
    final bw = maxX - minX + 1, bh = maxY - minY + 1;
    // 0 = unseen, 1 = reaches outside, 2 = candidate pocket (assigned later)
    final open = Uint8List(bw * bh);
    final oq = Queue<int>();
    bool openable(int x, int y) =>
        transparent(x, y) && filled[y * w + x] == 0;
    for (var x = minX; x <= maxX; x++) {
      for (final y in [minY, maxY]) {
        if (openable(x, y) && open[(y - minY) * bw + (x - minX)] == 0) {
          open[(y - minY) * bw + (x - minX)] = 1;
          oq.add((y - minY) * bw + (x - minX));
        }
      }
    }
    for (var y = minY; y <= maxY; y++) {
      for (final x in [minX, maxX]) {
        if (openable(x, y) && open[(y - minY) * bw + (x - minX)] == 0) {
          open[(y - minY) * bw + (x - minX)] = 1;
          oq.add((y - minY) * bw + (x - minX));
        }
      }
    }
    while (oq.isNotEmpty) {
      final i = oq.removeFirst();
      final x = i % bw + minX, y = i ~/ bw + minY;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < minX || ny < minY || nx > maxX || ny > maxY) continue;
          final bi = (ny - minY) * bw + (nx - minX);
          if (open[bi] != 0 || !openable(nx, ny)) continue;
          open[bi] = 1;
          oq.add(bi);
        }
      }
    }
    // Collect enclosed pockets component by component (size-capped).
    final pocketCap = filledCount;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final bi = (y - minY) * bw + (x - minX);
        if (open[bi] != 0 || !openable(x, y)) continue;
        // BFS this pocket to measure it before committing.
        final pocket = <int>[];
        final pq = Queue<int>()..add(y * w + x);
        open[bi] = 2;
        while (pq.isNotEmpty) {
          final i = pq.removeFirst();
          pocket.add(i);
          final px = i % w, py = i ~/ w;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = px + dx, ny = py + dy;
              if (nx < minX || ny < minY || nx > maxX || ny > maxY) continue;
              final nbi = (ny - minY) * bw + (nx - minX);
              if (open[nbi] != 0 || !openable(nx, ny)) continue;
              open[nbi] = 2;
              pq.add(ny * w + nx);
            }
          }
        }
        if (pocket.length <= pocketCap) {
          for (final i in pocket) {
            filled[i] = 1;
          }
        }
      }
    }
  }

  // 3) Write pixels — soft alpha on the region's outer boundary so the new
  //    edge sits comfortably next to the segmentation's feathered edges.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (filled[y * w + x] == 0) continue;
      var boundary = false;
      for (var dy = -1; dy <= 1 && !boundary; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          // Neighbors outside the image count as boundary too — a restored
          // region ending at the photo edge should still soften.
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (transparent(nx, ny) && filled[ny * w + nx] == 0) {
            boundary = true;
            break;
          }
        }
      }
      final p = orig.getPixel(x, y);
      im.setPixelRgba(
        x,
        y,
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
        boundary ? 170 : 255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

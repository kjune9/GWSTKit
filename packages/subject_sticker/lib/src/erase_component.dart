import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Request bundle for [eraseComponentAt] — a single object so it can be
/// passed straight to Flutter's `compute()`.
class EraseComponentRequest {
  const EraseComponentRequest(this.cutoutPng, {required this.x, required this.y});

  /// Transparent cutout PNG (e.g. from `trySubjectCutout`).
  final Uint8List cutoutPng;

  /// Tap position in image pixels.
  final int x;
  final int y;
}

/// Erases the connected opaque component under (or near) the tap point of a
/// transparent cutout PNG.
///
/// Segmentation sometimes drags in stray bits that are not the subject
/// (a corner of the table, a scrap of foil). Those usually come out as
/// blobs disconnected from the main subject, so "tap a piece to delete it"
/// is enough to clean them up — no eraser brush needed.
///
/// How it works:
/// 1. Seed = the tapped pixel if it is opaque, otherwise the nearest opaque
///    pixel within a small radius (~1.5% of the long side, min 12 px), so a
///    slightly-off tap on a thin sliver still lands.
/// 2. BFS flood fill over the 8-connected region of pixels with alpha > 8
///    (the same threshold `stickerize` uses for its bounding box), clearing
///    each pixel to fully transparent — feathered edges go with the body.
///
/// Returns the updated PNG, or `null` when no opaque pixel is near the tap
/// (nothing to erase) or the bytes fail to decode. Run inside `compute()` —
/// the flood fill plus PNG re-encode is too slow for the UI thread.
Uint8List? eraseComponentAt(EraseComponentRequest req) {
  final im = img.decodePng(req.cutoutPng);
  if (im == null) return null;
  final w = im.width, h = im.height;

  bool opaque(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && im.getPixel(x, y).a > 8;

  // 1) Seed — tapped pixel, or the nearest opaque pixel within the radius.
  var sx = req.x, sy = req.y;
  if (!opaque(sx, sy)) {
    final radius = math.max(12, (math.max(w, h) * 0.015).round());
    var best = -1, bx = 0, by = 0;
    for (var y = math.max(0, sy - radius);
        y <= math.min(h - 1, sy + radius);
        y++) {
      for (var x = math.max(0, sx - radius);
          x <= math.min(w - 1, sx + radius);
          x++) {
        if (im.getPixel(x, y).a <= 8) continue;
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

  // 2) BFS flood fill (8-connected), clearing the component to transparent.
  final visited = Uint8List(w * h);
  final queue = Queue<int>()..add(sy * w + sx);
  visited[sy * w + sx] = 1;
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    final x = i % w, y = i ~/ w;
    im.setPixelRgba(x, y, 0, 0, 0, 0);
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (!opaque(nx, ny)) continue;
        final ni = ny * w + nx;
        if (visited[ni] == 1) continue;
        visited[ni] = 1;
        queue.add(ni);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

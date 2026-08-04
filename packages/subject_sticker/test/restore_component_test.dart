import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:subject_sticker/subject_sticker.dart';

/// Builds a PNG from a painter callback.
Uint8List pngOf(int w, int h, void Function(img.Image) paint) {
  final im = img.Image(width: w, height: h, numChannels: 4);
  paint(im);
  return Uint8List.fromList(img.encodePng(im));
}

void fillRect(img.Image im, int x0, int y0, int x1, int y1, int r, int g,
    int b, int a) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      im.setPixelRgba(x, y, r, g, b, a);
    }
  }
}

int opaqueCount(Uint8List png) {
  final im = img.decodePng(png)!;
  var n = 0;
  for (final p in im) {
    if (p.a > 8) n++;
  }
  return n;
}

void main() {
  // Original: left half red, right half green. 60x60.
  final original = pngOf(60, 60, (im) {
    fillRect(im, 0, 0, 30, 60, 200, 30, 30, 255);
    fillRect(im, 30, 0, 60, 60, 30, 160, 60, 255);
  });

  test('restores the transparent region matching the seed color', () {
    // Cutout kept only the red half; the green half was cut away.
    final cutout = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 30, 60, 200, 30, 30, 255);
    });
    final out = restoreRegionAt(
      RestoreRegionRequest(cutout, original, x: 45, y: 30),
    );
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    // Tapped pixel came back with the original's green.
    final p = im.getPixel(45, 30);
    expect(p.a, greaterThan(200));
    expect(p.g.toInt(), 160);
    // The red half was opaque already — untouched.
    expect(im.getPixel(10, 30).r.toInt(), 200);
    // Roughly the green half (30*60=1800) was added to the red half's 1800.
    final n = opaqueCount(out);
    expect(n, greaterThan(3300));
    expect(n, lessThanOrEqualTo(3600));
  });

  test('stops at color boundaries instead of flooding everything', () {
    // Everything is transparent — only seed-similar pixels may come back.
    final cutout = pngOf(60, 60, (_) {});
    final out = restoreRegionAt(
      RestoreRegionRequest(cutout, original, x: 45, y: 30),
    );
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    // Green side restored, red side still transparent.
    expect(im.getPixel(45, 30).a.toInt(), greaterThan(200));
    expect(im.getPixel(10, 30).a.toInt(), lessThanOrEqualTo(8));
    expect(opaqueCount(out), lessThanOrEqualTo(1800));
  });

  test('fills enclosed pockets (specular glints) regardless of color', () {
    // Green face with a red 6x6 "glint" in the middle — the seed flood
    // skips it, but it is fully enclosed so the pocket pass fills it.
    final glossy = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 60, 60, 30, 160, 60, 255);
      fillRect(im, 27, 27, 33, 33, 220, 40, 40, 255);
    });
    final cutout = pngOf(60, 60, (_) {});
    final out = restoreRegionAt(
      RestoreRegionRequest(cutout, glossy, x: 10, y: 10),
    );
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    final p = im.getPixel(30, 30);
    expect(p.a.toInt(), greaterThan(100)); // the glint came back...
    expect(p.r.toInt(), greaterThan(150)); // ...with its own (red) pixels
    expect(opaqueCount(out), 3600); // the whole face, no perforation
  });

  test('returns null when there is nothing to restore near the tap', () {
    // Fully opaque cutout — no transparent pixel anywhere.
    final cutout = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 60, 60, 120, 120, 120, 255);
    });
    final out = restoreRegionAt(
      RestoreRegionRequest(cutout, original, x: 30, y: 30),
    );
    expect(out, isNull);
  });

  test('forgives a slightly-off tap by snapping to nearby transparency', () {
    // Only a small hole is transparent; tap lands just outside it.
    final cutout = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 60, 60, 200, 30, 30, 255);
      fillRect(im, 40, 20, 50, 30, 0, 0, 0, 0); // the hole
    });
    final out = restoreRegionAt(
      RestoreRegionRequest(cutout, original, x: 38, y: 25), // 2px outside
    );
    expect(out, isNotNull);
    expect(img.decodePng(out!)!.getPixel(45, 25).a.toInt(), greaterThan(100));
  });

  test('maps coordinates when the original is a different resolution', () {
    // Original at 2x (120x120) — must be resampled onto the 60x60 cutout.
    final original2x = pngOf(120, 120, (im) {
      fillRect(im, 0, 0, 60, 120, 200, 30, 30, 255);
      fillRect(im, 60, 0, 120, 120, 30, 160, 60, 255);
    });
    final cutout = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 30, 60, 200, 30, 30, 255);
    });
    final out = restoreRegionAt(
      RestoreRegionRequest(cutout, original2x, x: 45, y: 30),
    );
    expect(out, isNotNull);
    final p = img.decodePng(out!)!.getPixel(45, 30);
    expect(p.a.toInt(), greaterThan(200));
    expect(p.g.toInt(), closeTo(160, 10));
  });
}

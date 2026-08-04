import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:subject_sticker/subject_sticker.dart';

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

void main() {
  // Original: left half red, right half green — the brush must not care.
  final original = pngOf(60, 60, (im) {
    fillRect(im, 0, 0, 30, 60, 200, 30, 30, 255);
    fillRect(im, 30, 0, 60, 60, 30, 160, 60, 255);
  });

  test('restore stroke fills across color boundaries', () {
    final cutout = pngOf(60, 60, (_) {}); // everything cut away
    final out = applyStroke(StrokeRequest(
      cutout,
      originalBytes: original,
      points: [10, 30, 50, 30], // horizontal line crossing red→green
      radius: 5,
    ));
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    // Both sides of the color boundary came back — a flood could never
    // do this in one gesture.
    expect(im.getPixel(12, 30).a.toInt(), greaterThan(200));
    expect(im.getPixel(12, 30).r.toInt(), 200);
    expect(im.getPixel(48, 30).a.toInt(), greaterThan(200));
    expect(im.getPixel(48, 30).g.toInt(), 160);
    // Far from the stroke — untouched.
    expect(im.getPixel(30, 5).a.toInt(), lessThanOrEqualTo(8));
  });

  test('erase stroke clears opaque pixels under the line', () {
    final cutout = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 60, 60, 120, 120, 120, 255);
    });
    final out = applyStroke(StrokeRequest(
      cutout,
      points: [10, 30, 50, 30],
      radius: 5,
      erase: true,
    ));
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    expect(im.getPixel(30, 30).a.toInt(), lessThanOrEqualTo(8));
    expect(im.getPixel(30, 5).a.toInt(), 255); // outside the stroke
  });

  test('returns null when the stroke changes nothing', () {
    // Restore where everything is already opaque.
    final opaque = pngOf(60, 60, (im) {
      fillRect(im, 0, 0, 60, 60, 120, 120, 120, 255);
    });
    expect(
      applyStroke(StrokeRequest(
        opaque,
        originalBytes: original,
        points: [10, 30, 50, 30],
        radius: 5,
      )),
      isNull,
    );
    // Erase where everything is already transparent.
    final empty = pngOf(60, 60, (_) {});
    expect(
      applyStroke(StrokeRequest(
        empty,
        points: [10, 30, 50, 30],
        radius: 5,
        erase: true,
      )),
      isNull,
    );
  });

  test('single point paints one disc', () {
    final cutout = pngOf(60, 60, (_) {});
    final out = applyStroke(StrokeRequest(
      cutout,
      originalBytes: original,
      points: [45, 30],
      radius: 6,
    ));
    expect(out, isNotNull);
    final im = img.decodePng(out!)!;
    expect(im.getPixel(45, 30).a.toInt(), greaterThan(200));
    expect(im.getPixel(45, 30).g.toInt(), 160);
    expect(im.getPixel(10, 30).a.toInt(), lessThanOrEqualTo(8));
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Builds a raw RGBA image (not PNG) representing a logo: transparent
/// background with a horizontal band of [inkR]/[inkG]/[inkB] across the
/// middle (mimics text stroke pixels). Returns the ui.Image.
Future<ui.Image> _makeLogoImage({
  required int inkR,
  required int inkG,
  required int inkB,
  int width = 120,
  int height = 48,
}) async {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final inBand = y > height * 0.35 && y < height * 0.65;
      if (inBand) {
        bytes[i] = inkR;
        bytes[i + 1] = inkG;
        bytes[i + 2] = inkB;
        bytes[i + 3] = 255;
      } else {
        bytes[i + 3] = 0; // fully transparent
      }
    }
  }
  final descriptor = ui.ImageDescriptor.raw(
    await ui.ImmutableBuffer.fromUint8List(bytes),
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  descriptor.dispose();
  return frame.image;
}

Future<double> _luminanceOf(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  final raw = data!.buffer.asUint8List();
  final stride = img.width > 128 ? 4 : 1;
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < raw.length; i += 4 * stride) {
    final r = raw[i] / 255.0;
    final g = raw[i + 1] / 255.0;
    final b = raw[i + 2] / 255.0;
    final a = raw[i + 3] / 255.0;
    if (a < 0.03) continue;
    sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) * a;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('white logo text is bright enough to display on dark bg', () async {
    final img = await _makeLogoImage(inkR: 255, inkG: 255, inkB: 255);
    final lum = await _luminanceOf(img);
    expect(lum, greaterThan(0.9)); // ≈1.0 expected
    expect(lum, greaterThanOrEqualTo(0.38)); // passes the widget threshold
  });

  test('black logo text is too dark for the dark bg → title fallback', () async {
    final img = await _makeLogoImage(inkR: 0, inkG: 0, inkB: 0);
    final lum = await _luminanceOf(img);
    expect(lum, lessThan(0.38));
  });

  test('mid-grey ink falls below threshold → title fallback', () async {
    final img = await _makeLogoImage(inkR: 80, inkG: 80, inkB: 80);
    final lum = await _luminanceOf(img);
    expect(lum, lessThan(0.38));
  });

  test('bright gold ink passes threshold', () async {
    final img = await _makeLogoImage(inkR: 255, inkG: 200, inkB: 40);
    final lum = await _luminanceOf(img);
    expect(lum, greaterThanOrEqualTo(0.38));
  });
}

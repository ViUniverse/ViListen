import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureAsset = 'assets/test_audio/player_fixture_2s.wav';

// Fixture: assets/test_audio/player_fixture_2s.wav
// PCM signed 16-bit LE, 48_000 Hz, mono, 96_000 frames, duration 2.000 s.
// Provenance: synthetic 1 kHz square tone generated in-repository; no
// third-party recording, URL, or copyrighted audio source was used.
// Generator: for frame n, sample = +8192 when (n % 48) < 24, otherwise -8192;
// each sample is packed as signed 16-bit little-endian PCM.
// SHA-256 of the entire WAV (header + data):
// 7c0075e0719e58447341850c008eda6effe6f10eefdcd6952c63926378cc8ab2
const _fixtureSha256 =
    '7c0075e0719e58447341850c008eda6effe6f10eefdcd6952c63926378cc8ab2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local audio fixture is registered and deterministic', () async {
    final loaded = await rootBundle.load(_fixtureAsset);
    final bytes = loaded.buffer.asUint8List(
      loaded.offsetInBytes,
      loaded.lengthInBytes,
    );

    expect(bytes.length, 192044);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(_uint16(bytes, 20), 1); // PCM format.
    expect(_uint16(bytes, 22), 1); // Mono.
    expect(_uint32(bytes, 24), 48000); // Sample rate.
    expect(_uint32(bytes, 28), 96000); // Byte rate.
    expect(_uint16(bytes, 32), 2); // Block align.
    expect(_uint16(bytes, 34), 16); // Bits per sample.
    expect(_uint32(bytes, 40), 192000); // Data bytes.
    expect(_uint32(bytes, 40) / _uint32(bytes, 28), 2.0);
    expect(sha256.convert(bytes).toString(), _fixtureSha256);
  });
}

int _uint16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _uint32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

// lib/services/crc32.dart
//
// Standard CRC-32 (IEEE 802.3, polynomial 0xEDB88320 reflected) — the same
// checksum zlib, ZIP and the `archive` package produce, and the one the
// wallet firmware sends in the audio "end" packet.
// Written out here so the app doesn't need an extra package for it.

final List<int> _table = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _table[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
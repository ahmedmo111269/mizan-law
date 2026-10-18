import 'dart:math';

abstract final class IdGenerator {
  static final Random _random = Random.secure();

  static String uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
    final joined = hex.join();
    return '${joined.substring(0, 8)}-${joined.substring(8, 12)}-'
        '${joined.substring(12, 16)}-${joined.substring(16, 20)}-'
        '${joined.substring(20)}';
  }
}

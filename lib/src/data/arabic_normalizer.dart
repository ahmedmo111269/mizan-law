abstract final class ArabicNormalizer {
  static const _diacritics = <int>{
    0x0610, 0x0611, 0x0612, 0x0613, 0x0614, 0x0615, 0x0616, 0x0617,
    0x0618, 0x0619, 0x061A, 0x064B, 0x064C, 0x064D, 0x064E, 0x064F,
    0x0650, 0x0651, 0x0652, 0x0653, 0x0654, 0x0655, 0x0656, 0x0657,
    0x0658, 0x0659, 0x065A, 0x065B, 0x065C, 0x065D, 0x065E, 0x065F,
    0x0670,
  };

  /// Search-only normalization. The entered display value is never replaced.
  static String text(String input) {
    final output = StringBuffer();
    var pendingSpace = false;
    for (final rune in input.runes) {
      if (rune == 0x0640 || _diacritics.contains(rune)) continue;
      final mapped = switch (rune) {
        0x0622 || 0x0623 || 0x0625 => 0x0627, // أ إ آ -> ا
        0x0649 => 0x064A, // ى -> ي
        >= 0x0660 && <= 0x0669 => 0x0030 + (rune - 0x0660),
        >= 0x06F0 && <= 0x06F9 => 0x0030 + (rune - 0x06F0),
        _ => rune,
      };
      final char = String.fromCharCode(mapped);
      if (_isWhitespace(char) || _isPunctuation(char)) {
        pendingSpace = output.length > 0;
        continue;
      }
      if (pendingSpace) output.write(' ');
      pendingSpace = false;
      output.write(char.toLowerCase());
    }
    return output.toString().trim();
  }

  static String digits(String input) => String.fromCharCodes(
        input.runes.map((rune) => switch (rune) {
          >= 0x0660 && <= 0x0669 => 0x0030 + (rune - 0x0660),
          >= 0x06F0 && <= 0x06F9 => 0x0030 + (rune - 0x06F0),
          _ => rune,
        }),
      ).replaceAll(RegExp(r'[^0-9]'), '');

  static bool _isWhitespace(String char) =>
      char.trim().isEmpty || char == '\u00A0';

  static bool _isPunctuation(String char) =>
      RegExp(r'[.,،؛:!?؟()]').hasMatch(char);
}

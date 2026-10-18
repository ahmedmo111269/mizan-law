import 'package:flutter_test/flutter_test.dart';

import '../../lib/src/data/arabic_normalizer.dart';

void main() {
  test('search-only Arabic normalization preserves the entered spelling rules', () {
    expect(ArabicNormalizer.text('أَحـمَد  عليّ'), 'احمد علي');
    expect(ArabicNormalizer.text('على'), 'علي');
    expect(ArabicNormalizer.text('مدرسة'), 'مدرسة');
  });

  test('Arabic-Indic and Persian digits normalize to ASCII digits', () {
    expect(ArabicNormalizer.digits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    expect(ArabicNormalizer.digits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
  });
}

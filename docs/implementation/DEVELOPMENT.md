# الإعداد والتشغيل والاختبار

## المتطلبات

- Flutter SDK 3.29 أو أحدث، مع Dart الذي يأتي معه.
- Python 3.10 أو أحدث لاختبارات عقد SQLite.
- لتشغيل Windows: Windows SDK وVisual Studio مع أدوات C++ لسطح المكتب.
- لتشغيل Android: Android SDK وجهاز أو محاكي مُهيأ عبر `flutter doctor`.

لا يلزم اتصال بالإنترنت أثناء تشغيل التطبيق بعد البناء. جلب Flutter والحزم وقت الإعداد يحتاج اتصال تطوير عاديًا.

## إعداد المشروع

من جذر المستودع:

```sh
./scripts/bootstrap_flutter.sh
```

ينشئ السكربت ملفات تشغيل Windows وAndroid، ثم ينفذ `flutter pub get`. لا يشغّل التطبيق ولا ينشئ سجلات أشخاص حقيقية. إذا كانت ملفات المنصة موجودة مسبقًا، راجع تغييرات `git diff` بعد تشغيل `flutter create` قبل قبولها.

تحقق من توفر الأهداف:

```sh
flutter doctor
flutter devices
```

## التشغيل

```sh
flutter run -d windows
```

أو استبدل `windows` بمعرّف جهاز Android الظاهر في `flutter devices`:

```sh
flutter run -d <device-id>
```

يستخدم التطبيق مجلد دعم التطبيق الذي توفره المنصة، ويضع داخله فهرس القواعد وسجل الأشخاص المشترك ومجلد قواعد العمل. راجع [حدود الاستخدام المحلي](LOCAL_ONLY_LIMITS.md) قبل تشغيله؛ استخدم بيانات اصطناعية فقط.

## الاختبارات

```sh
flutter analyze
flutter test --reporter expanded
python3 scripts/test_sqlite_contract.py
```

- `flutter analyze`: يحلل مصدر Dart وحزم التطبيق.
- `flutter test`: يشغّل اختبارات المستودع وSQLite والواجهات عبر `sqflite_common_ffi` وFlutter Test.
- `scripts/test_sqlite_contract.py`: يختبر ملفات SQL مباشرة بمكتبة `sqlite3` في Python؛ لا يثبت وحده تكامل Flutter أو سلوك sqflite الأصلي.

يفحص `.github/workflows/flutter.yml` هذه الأوامر عند الدفع أو فتح PR. نجاح اختبار واحد لا يُستنتج منه نجاح بقية الأوامر.

## ملفات التشغيل المحلية

تُستبعد ملفات `.sqlite` وملفات journal المؤقتة من Git بواسطة `.gitignore`. لا تضع قاعدة مستخدم حقيقية داخل المستودع، أو في مخرجات الاختبار أو تقارير الأعطال. لا ترفع قواعد التطبيق أو لقطات شاشة تحتوي بيانات موكلين.

## استكشاف أخطاء شائعة

- **`flutter: not found`:** ثبت Flutter 3.29+ وأضفه إلى `PATH`، ثم أعد الأمر.
- **لا يظهر هدف Windows:** يلزم تشغيل الأمر على Windows مع أدوات C++ المطلوبة؛ لا يكفي إنشاء ملفات runner على نظام آخر.
- **لم يظهر جهاز Android:** راجع `flutter doctor`، وتأكد من إعداد Android SDK وقبول تراخيصه.
- **فشل جلب الحزم:** تحقق من اتصال إعداد التطوير إلى pub.dev، ثم أعد `flutter pub get`. لا يعتمد تشغيل التطبيق نفسه على خدمة مدفوعة أو خادم بعيد.
- **فشل اختبار قاعدة البيانات:** أرفق نص الخطأ دون قاعدة بيانات فعلية أو حقول شخصية؛ الاختبارات المرفقة لا تحتاج بيانات خارجية.
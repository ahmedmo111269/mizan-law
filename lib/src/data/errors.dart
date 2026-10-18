import '../domain/models.dart';

sealed class MizanException implements Exception {
  const MizanException(this.userMessage);
  final String userMessage;

  @override
  String toString() => userMessage;
}

class ValidationException extends MizanException {
  const ValidationException(super.userMessage);
}

class DuplicateClientException extends MizanException {
  const DuplicateClientException()
      : super('هذا الشخص مسجل كموكل بالفعل في القاعدة الحالية.');
}

class SimilarPeopleException extends MizanException {
  const SimilarPeopleException(this.candidates)
      : super('عُثر على أشخاص متشابهين. راجع النتائج قبل إنشاء هوية جديدة.');

  final List<PersonCandidate> candidates;
}

class RecordNotFoundException extends MizanException {
  const RecordNotFoundException()
      : super('تعذر العثور على السجل. ربما تغيرت البيانات أو القاعدة النشطة.');
}

class StorageException extends MizanException {
  const StorageException()
      : super('تعذر إتمام الحفظ. لم تُعتمد العملية؛ تحقق من المساحة ثم أعد المحاولة.');
}

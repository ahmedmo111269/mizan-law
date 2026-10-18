import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../data/client_repository.dart';
import '../../data/errors.dart';
import '../../data/id_generator.dart';
import '../../domain/models.dart';
import '../../shared/diagnostics.dart';

class ClientEditorScreen extends StatefulWidget {
  const ClientEditorScreen({
    required this.controller,
    this.editing,
    super.key,
  });

  final AppController controller;
  final ClientRecord? editing;

  bool get isEditing => editing != null;

  @override
  State<ClientEditorScreen> createState() => _ClientEditorScreenState();
}

class _ClientEditorScreenState extends State<ClientEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.person.displayName ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.editing?.person.phone ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.editing?.person.email ?? '',
  );
  final String _operationId = IdGenerator.uuidV4();
  Timer? _matchTimer;
  List<PersonCandidate> _matches = const <PersonCandidate>[];
  PersonCandidate? _selectedPerson;
  PersonKind _kind = PersonKind.natural;
  bool _checkingMatches = false;
  bool _hasCheckedMatches = false;
  bool _saving = false;
  bool _similarityConfirmed = false;
  final Set<String> _confirmedSimilarPersonIds = <String>{};
  String? _error;
  int _matchRequest = 0;

  ClientRepository get _repository => widget.controller.clients;

  @override
  void initState() {
    super.initState();
    _kind = widget.editing?.person.kind ?? PersonKind.natural;
    if (!widget.isEditing) {
      _name.addListener(_scheduleMatchCheck);
      _phone.addListener(_scheduleMatchCheck);
      _email.addListener(_scheduleMatchCheck);
    }
  }

  @override
  void dispose() {
    _matchTimer?.cancel();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _scheduleMatchCheck() {
    _matchTimer?.cancel();
    if (_selectedPerson != null || widget.isEditing) return;
    _similarityConfirmed = false;
    _confirmedSimilarPersonIds.clear();
    _hasCheckedMatches = false;
    _matchTimer = Timer(const Duration(milliseconds: 280), _findMatches);
  }

  Future<void> _findMatches() async {
    if (!mounted) return;
    final request = ++_matchRequest;
    final draft = PersonDraft(
      kind: _kind,
      displayName: _name.text,
      phone: _phone.text,
      email: _email.text,
    );
    if (draft.displayName.trim().length < 2 &&
        (draft.phone ?? '').trim().isEmpty &&
        (draft.email ?? '').trim().isEmpty) {
      if (mounted) {
        setState(() {
          _matches = const <PersonCandidate>[];
          _checkingMatches = false;
          _hasCheckedMatches = false;
        });
      }
      return;
    }
    setState(() => _checkingMatches = true);
    try {
      final found = await _repository.findPotentialMatches(draft);
      if (!mounted || request != _matchRequest) return;
      setState(() {
        _matches = found;
        _hasCheckedMatches = true;
        _error = null;
      });
    } catch (error) {
      Diagnostics.failure('client_duplicate_check', error);
      if (mounted && request == _matchRequest) {
        setState(() => _error = 'تعذر فحص السجل المشترك الآن. يمكنك إعادة المحاولة قبل الحفظ.');
      }
    } finally {
      if (mounted && request == _matchRequest) {
        setState(() => _checkingMatches = false);
      }
    }
  }

  Future<void> _selectPerson(PersonCandidate candidate) async {
    if (candidate.alreadyClient) return;
    final confirmed = await _confirmExistingIdentity(candidate);
    if (!confirmed || !mounted) return;
    _matchTimer?.cancel();
    _matchRequest++;
    setState(() {
      _selectedPerson = candidate;
      _kind = candidate.person.kind;
      _name.text = candidate.person.displayName;
      _phone.text = candidate.person.phone ?? '';
      _email.text = candidate.person.email ?? '';
      _matches = <PersonCandidate>[candidate];
      _checkingMatches = false;
      _error = null;
      _similarityConfirmed = false;
      _confirmedSimilarPersonIds.clear();
    });
  }

  void _clearSelectedPerson() {
    _matchTimer?.cancel();
    _matchRequest++;
    setState(() {
      _selectedPerson = null;
      _matches = const <PersonCandidate>[];
      _checkingMatches = false;
      _hasCheckedMatches = false;
      _error = null;
      _similarityConfirmed = false;
      _confirmedSimilarPersonIds.clear();
    });
    _scheduleMatchCheck();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (widget.isEditing && !await _confirmSharedIdentityEdit()) return;
    if (!widget.isEditing &&
        _selectedPerson == null &&
        _matches.isNotEmpty &&
        !_similarityConfirmed) {
      final confirmed = await _confirmSimilarPeople();
      if (!confirmed || !mounted) return;
      setState(() {
        _similarityConfirmed = true;
        _confirmedSimilarPersonIds.addAll(
          _matches.map((candidate) => candidate.person.id),
        );
      });
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.editing case final editing?) {
        await _repository.updateIdentity(
          engagementId: editing.engagementId,
          displayName: _name.text,
          phone: _phone.text,
          email: _email.text,
        );
      } else {
        await _repository.createClient(
          operationId: _operationId,
          existingPersonId: _selectedPerson?.person.id,
          newPerson: _selectedPerson == null
              ? PersonDraft(
                  kind: _kind,
                  displayName: _name.text,
                  phone: _phone.text,
                  email: _email.text,
                )
              : null,
          reviewedSimilarPersonIds: _confirmedSimilarPersonIds.toList(growable: false),
        );
      }
      Diagnostics.event(widget.isEditing ? 'client_identity_updated' : 'client_created');
      widget.controller.markDataChanged();
      if (mounted) Navigator.of(context).pop(true);
    } on SimilarPeopleException catch (error) {
      if (mounted) {
        setState(() {
          _matches = error.candidates;
          _similarityConfirmed = false;
          _error = 'عُثر على أشخاص متشابهين. اختر هوية موجودة أو أكد إنشاء هوية مستقلة.';
        });
      }
    } on MizanException catch (error) {
      Diagnostics.failure('client_save', error);
      if (mounted) setState(() => _error = error.userMessage);
    } catch (error) {
      Diagnostics.failure('client_save', error);
      if (mounted) setState(() => _error = 'تعذر الحفظ. بقيت البيانات في النموذج؛ أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmExistingIdentity(PersonCandidate candidate) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.person_search_rounded),
          title: const Text('تأكيد استخدام هوية مشتركة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('سبب ظهور النتيجة: ${candidate.matchReason}.'),
                const SizedBox(height: 10),
                Text('الاسم: ${candidate.person.displayName}'),
                Text('الهاتف: ${candidate.person.phone ?? 'غير مسجل'}'),
                Text('البريد: ${candidate.person.email ?? 'غير مسجل'}'),
                const SizedBox(height: 10),
                const Text(
                  'تشابه الاسم لا يثبت وحدة الشخص. راجع البيانات بنفسك؛ لن تُستخدم الهوية إلا بعد تأكيدك الصريح.',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('العودة'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد أنها الهوية نفسها'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmSimilarPeople() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.person_search_rounded),
          title: const Text('مراجعة احتمال التكرار'),
          content: const Text(
            'ظهرت أسماء أو وسائل تواصل متشابهة. التشابه لا يثبت وحدة الشخص، ولن تُدمج الهوية تلقائيًا. هل راجعت النتائج وتريد إنشاء هوية مستقلة؟',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('العودة للمراجعة'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إنشاء هوية مستقلة'),
            ),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmSharedIdentityEdit() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.public_rounded),
          title: const Text('تعديل هوية مشتركة'),
          content: const Text(
            'هذه البيانات جزء من سجل الأشخاص المشترك بين قواعد المكتب. سيظهر التعديل في البطاقات التي تستخدم الهوية نفسها. هل تريد المتابعة؟',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد التعديل'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: _saving ? null : () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(widget.isEditing ? 'تعديل بيانات الموكل' : 'إضافة موكل'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: <Widget>[
                    if (!widget.isEditing) ...<Widget>[
                      const _SharedIdentityNote(),
                      const SizedBox(height: 18),
                    ],
                    if (_error != null) ...<Widget>[
                      _InlineError(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    if (widget.isEditing)
                      const _SectionHeading(
                        title: 'الهوية المشتركة',
                        subtitle: 'لن تتغير علاقة الموكل بهذه القاعدة.',
                      )
                    else
                      const _SectionHeading(
                        title: 'ابحث قبل إنشاء هوية',
                        subtitle: 'إعادة استخدام هوية موجودة تمنع تكرار الشخص دون دمج سجلات متشابهة.',
                      ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<PersonKind>(
                      initialValue: _kind,
                      decoration: const InputDecoration(
                        labelText: 'نوع الشخص',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: const <DropdownMenuItem<PersonKind>>[
                        DropdownMenuItem(
                          value: PersonKind.natural,
                          child: Text('شخص طبيعي'),
                        ),
                        DropdownMenuItem(
                          value: PersonKind.organization,
                          child: Text('جهة / مؤسسة'),
                        ),
                      ],
                      onChanged: widget.isEditing || _selectedPerson != null
                          ? null
                          : (value) {
                              if (value != null) setState(() => _kind = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey<String>('client-name-field'),
                      controller: _name,
                      enabled: _selectedPerson == null,
                      autofocus: !widget.isEditing,
                      textDirection: TextDirection.rtl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'الاسم',
                        hintText: 'اكتب الاسم كما تريد عرضه',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.isEmpty) return 'الاسم مطلوب.';
                        if (name.length > 200) return 'الحد الأقصى 200 حرف.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      enabled: _selectedPerson == null,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        labelText: 'الهاتف (اختياري)',
                        prefixIcon: Icon(Icons.phone_outlined),
                        helperText: 'يمكن تركه فارغًا.',
                      ),
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      enabled: _selectedPerson == null,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      maxLength: 254,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني (اختياري)',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: _validateEmail,
                    ),
                    if (_selectedPerson != null) ...<Widget>[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _clearSelectedPerson,
                        icon: const Icon(Icons.change_circle_outlined),
                        label: const Text('اختيار هوية أخرى أو إنشاء هوية جديدة'),
                      ),
                    ],
                    if (!widget.isEditing && _selectedPerson == null) ...<Widget>[
                      const SizedBox(height: 10),
                      _MatchResults(
                        matches: _matches,
                        checking: _checkingMatches,
                        hasChecked: _hasCheckedMatches,
                        onSelect: _selectPerson,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(widget.isEditing ? Icons.save_outlined : Icons.person_add_alt_1_rounded),
                      label: Text(_saving
                          ? 'جارٍ الحفظ…'
                          : widget.isEditing
                              ? 'حفظ التعديل'
                              : _selectedPerson == null
                                  ? 'حفظ الموكل'
                                  : 'استخدام الهوية وإضافة الموكل'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'[^0-9٠-٩۰-۹]'), '');
    if (!RegExp(r'^[+0-9٠-٩۰-۹().\s-]+$').hasMatch(phone) ||
        digits.length < 7 ||
        digits.length > 15 ||
        phone.length > 30) {
      return 'أدخل رقمًا من 7 إلى 15 رقمًا أو اترك الحقل فارغًا.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'أدخل بريدًا صحيحًا أو اترك الحقل فارغًا.';
    }
    return null;
  }
}

class _MatchResults extends StatelessWidget {
  const _MatchResults({
    required this.matches,
    required this.checking,
    required this.hasChecked,
    required this.onSelect,
  });

  final List<PersonCandidate> matches;
  final bool checking;
  final bool hasChecked;
  final ValueChanged<PersonCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (matches.isEmpty) {
      return Text(
        hasChecked
            ? 'لم يظهر شخص قريب في السجل المشترك؛ يمكنك متابعة إنشاء هوية جديدة.'
            : 'اكتب الاسم أو وسيلة تواصل للتحقق من السجل المشترك.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'أشخاص قد يتشابهون — التشابه لا يعني أنهم الشخص نفسه',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        for (final candidate in matches)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_search_outlined),
              title: Text(candidate.person.displayName),
              subtitle: Text(
                candidate.alreadyClient
                    ? '${candidate.matchReason} · موكل مسجل بالفعل في هذه القاعدة'
                    : candidate.matchReason,
              ),
              trailing: candidate.alreadyClient
                  ? const Icon(Icons.check_circle_outline_rounded)
                  : TextButton(
                      onPressed: () => onSelect(candidate),
                      child: const Text('استخدام'),
                    ),
              enabled: !candidate.alreadyClient,
            ),
          ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 4),
          Text(subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ],
      );
}

class _SharedIdentityNote extends StatelessWidget {
  const _SharedIdentityNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'الاسم ووسائل الاتصال هوية مشتركة بين قواعد المكتب. علاقة الموكل ستُنشأ في القاعدة النشطة فقط.',
              ),
            ),
          ],
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFCEEEF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFA33135)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, color: Color(0xFFA33135)),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: Color(0xFFA33135)))),
          ],
        ),
      );
}

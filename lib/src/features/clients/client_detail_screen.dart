import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../data/client_repository.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';
import 'client_editor_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({
    required this.controller,
    required this.engagementId,
    super.key,
  });

  final AppController controller;
  final String engagementId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Future<ClientRecord?> _record;
  bool _working = false;

  ClientRepository get _repository => widget.controller.clients;

  @override
  void initState() {
    super.initState();
    _record = _repository.getClient(widget.engagementId);
  }

  void _reload() => setState(() => _record = _repository.getClient(widget.engagementId));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('بطاقة الموكل'),
        ),
        body: FutureBuilder<ClientRecord?>(
          future: _record,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DetailState(
                icon: Icons.error_outline_rounded,
                title: 'تعذر فتح البطاقة',
                message: 'لم تُحمّل بيانات الهوية أو علاقة الموكل.',
                actionLabel: 'إعادة المحاولة',
                onAction: _reload,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final client = snapshot.data;
            if (client == null) {
              return _DetailState(
                icon: Icons.search_off_rounded,
                title: 'السجل غير متاح',
                message: 'قد تكون القاعدة النشطة قد تغيرت أو لم يعد السجل موجودًا.',
                actionLabel: 'العودة',
                onAction: () => Navigator.maybePop(context),
              );
            }
            return _buildCard(client);
          },
        ),
      );

  Widget _buildCard(ClientRecord client) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final body = ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _identityCard(client),
                      const SizedBox(height: 16),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: _relationshipCard(client)),
                            const SizedBox(width: 16),
                            Expanded(child: _scopeCard()),
                          ],
                        )
                      else ...<Widget>[
                        _relationshipCard(client),
                        const SizedBox(height: 16),
                        _scopeCard(),
                      ],
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: _working ? null : () => _edit(client),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('تعديل بيانات الهوية'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _working ? null : () => _changeStatus(client),
                            icon: Icon(client.status == ClientStatus.active
                                ? Icons.archive_outlined
                                : Icons.unarchive_outlined),
                            label: Text(client.status == ClientStatus.active
                                ? 'أرشفة علاقة الموكل'
                                : 'استعادة العلاقة'),
                          ),
                        ],
                      ),
                      if (_working) ...<Widget>[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
          return body;
        },
      );

  Widget _identityCard(ClientRecord client) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          client.person.kind == PersonKind.organization
                              ? Icons.business_outlined
                              : Icons.person_outline_rounded,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Text(
                          client.person.displayName,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                  _StatusPill(status: client.status),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                client.person.kind == PersonKind.organization ? 'جهة / مؤسسة' : 'شخص طبيعي',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              if (client.person.phone != null)
                _ContactRow(icon: Icons.phone_outlined, label: 'الهاتف', value: client.person.phone!)
              else
                const _ContactRow(
                  icon: Icons.phone_outlined,
                  label: 'الهاتف',
                  value: 'غير مسجل',
                ),
              const SizedBox(height: 10),
              if (client.person.email != null)
                _ContactRow(icon: Icons.email_outlined, label: 'البريد الإلكتروني', value: client.person.email!)
              else
                const _ContactRow(
                  icon: Icons.email_outlined,
                  label: 'البريد الإلكتروني',
                  value: 'غير مسجل',
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.share_outlined, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'بيانات الهوية مشتركة على مستوى تثبيت المكتب. التعديل هنا ينعكس على القواعد الأخرى التي تستخدم الهوية نفسها.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _relationshipCard(ClientRecord client) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('علاقة الموكل بهذه القاعدة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 12),
              _ContactRow(
                icon: Icons.storage_outlined,
                label: 'القاعدة',
                value: widget.controller.activeWorkspace.name,
              ),
              const SizedBox(height: 10),
              _ContactRow(
                icon: client.status == ClientStatus.active
                    ? Icons.check_circle_outline_rounded
                    : Icons.archive_outlined,
                label: 'الحالة',
                value: client.status == ClientStatus.active ? 'نشط' : 'مؤرشف',
              ),
              const SizedBox(height: 10),
              _ContactRow(
                icon: Icons.event_available_outlined,
                label: 'تاريخ التسجيل',
                value: _dateOnly(client.createdAtUtc),
              ),
              const SizedBox(height: 10),
              _ContactRow(
                icon: Icons.update_rounded,
                label: 'آخر تعديل',
                value: _dateOnly(client.updatedAtUtc),
              ),
            ],
          ),
        ),
      );

  Widget _scopeCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('حدود البطاقة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 10),
              const Text(
                'لا تُعرض هنا ملفات أو قضايا أو أدوار قانونية؛ لم تُنفّذ وحداتها بعد. الصفة القانونية تُسجل في سياق ملف أو قضية، وليست صفة ثابتة على هوية الشخص.',
              ),
            ],
          ),
        ),
      );

  Future<void> _edit(ClientRecord client) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClientEditorScreen(
          controller: widget.controller,
          editing: client,
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  Future<void> _changeStatus(ClientRecord client) async {
    final archiving = client.status == ClientStatus.active;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(archiving ? Icons.archive_outlined : Icons.unarchive_outlined),
            title: Text(archiving ? 'أرشفة علاقة الموكل؟' : 'استعادة علاقة الموكل؟'),
            content: Text(archiving
                ? 'ستُؤرشف العلاقة في «${widget.controller.activeWorkspace.name}» فقط. لن تُحذف هوية الشخص المشتركة أو أي علاقة أو سجل في قاعدة أخرى.'
                : 'ستُستعاد علاقة الموكل في هذه القاعدة فقط.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(archiving ? 'تأكيد الأرشفة' : 'تأكيد الاستعادة'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      await _repository.setArchived(
        engagementId: client.engagementId,
        archived: archiving,
      );
      widget.controller.markDataChanged();
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(archiving ? 'أُرشفت العلاقة.' : 'استُعيدت العلاقة.')),
        );
      }
    } on MizanException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.userMessage)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث الحالة. لم تُحذف أي بيانات.')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          Expanded(
            child: SelectableText(
              value,
              textDirection: value.contains('@') || RegExp(r'^[+0-9٠-٩۰-۹]').hasMatch(value)
                  ? TextDirection.ltr
                  : TextDirection.rtl,
            ),
          ),
        ],
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ClientStatus status;

  @override
  Widget build(BuildContext context) {
    final archived = status == ClientStatus.archived;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: archived
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Text(archived ? 'مؤرشف' : 'نشط'),
    );
  }
}

class _DetailState extends StatelessWidget {
  const _DetailState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 42),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null) ...<Widget>[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}

String _dateOnly(String value) {
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return 'غير متاح';
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day';
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../domain/models.dart';
import '../clients/client_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.controller,
    required this.onOpenClients,
    required this.onOpenClient,
    super.key,
  });

  final AppController controller;
  final void Function({String? query}) onOpenClients;
  final ValueChanged<String> onOpenClient;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Future<ClientPage>? _results;
  Future<int>? _count;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _count = widget.controller.clients.countClients(status: ClientStatus.active);
    _searchController.addListener(_onSearchChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _debounce?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.isBusy || !mounted) return;
    setState(() {
      _count = widget.controller.clients.countClients(status: ClientStatus.active);
      final query = _searchController.text.trim();
      _results = query.length >= 2
          ? widget.controller.clients.listClients(
              query: query,
              status: ClientStatus.active,
              pageSize: 6,
            )
          : null;
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _results = widget.controller.clients.listClients(
          query: query,
          status: ClientStatus.active,
          pageSize: 6,
        );
      });
    });
  }

  Future<void> _openAddClient() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ClientEditorScreen(controller: widget.controller),
        ),
      );
      if (!mounted) return;
      setState(() {
        _count = widget.controller.clients.countClients(status: ClientStatus.active);
        _results = _searchController.text.trim().length >= 2
            ? widget.controller.clients.listClients(
                query: _searchController.text.trim(),
                pageSize: 6,
              )
            : null;
      });
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _DevelopmentNotice(),
                const SizedBox(height: 24),
                Text(
                  'مكتب اليوم',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) => Text(
                    'مساحة عمل ${widget.controller.activeWorkspace.name}؛ ابدأ من الموكلين أو ابحث في سجلات هذه القاعدة.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 24),
                _SearchCard(
                  controller: _searchController,
                  results: _results,
                  onOpenAll: () => widget.onOpenClients(
                    query: _searchController.text.trim(),
                  ),
                  onOpenClient: widget.onOpenClient,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _adding ? null : _openAddClient,
                      icon: _adding
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('إضافة موكل'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.onOpenClients(),
                      icon: const Icon(Icons.people_alt_outlined),
                      label: const Text('فتح مركز الموكلين'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FutureBuilder<int>(
                  future: _count,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _CountError(onRetry: () {
                        setState(() => _count = widget.controller.clients.countClients(
                              status: ClientStatus.active,
                            ));
                      });
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.data == 0) {
                      return _EmptyWorkspace(onAddClient: _openAddClient);
                    }
                    return _AvailableWork(
                      count: snapshot.data!,
                      onOpenClients: () => widget.onOpenClients(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
}

class _DevelopmentNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3DA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF805000).withValues(alpha: 0.45)),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline_rounded, color: Color(0xFF805000)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'نسخة تطويرية محلية غير مشفّرة؛ استخدم بيانات اختبار اصطناعية فقط، ولا تُدخل بيانات موكلين حقيقية.',
                ),
              ),
            ],
          ),
        ),
      );
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.results,
    required this.onOpenAll,
    required this.onOpenClient,
  });

  final TextEditingController controller;
  final Future<ClientPage>? results;
  final VoidCallback onOpenAll;
  final ValueChanged<String> onOpenClient;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('بحث في الموكلين',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'اسم أو هاتف أو بريد إلكتروني',
                  hintText: 'اكتب للبحث داخل القاعدة الحالية',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => onOpenAll(),
              ),
              if (results != null) ...<Widget>[
                const SizedBox(height: 10),
                FutureBuilder<ClientPage>(
                  future: results,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('تعذر تنفيذ البحث. يمكنك إعادة المحاولة من مركز الموكلين.');
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final items = snapshot.data!.items;
                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا توجد نتائج مطابقة في هذه القاعدة.'),
                      );
                    }
                    return Column(
                      children: <Widget>[
                        for (final client in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline_rounded),
                            ),
                            title: Text(client.person.displayName),
                            subtitle: Text(_statusLabel(client.status)),
                            trailing: const Icon(Icons.chevron_left_rounded),
                            onTap: () => onOpenClient(client.engagementId),
                          ),
                        if (snapshot.data!.hasMore)
                          TextButton(
                            onPressed: onOpenAll,
                            child: const Text('عرض النتائج في مركز الموكلين'),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onOpenAll,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('البحث في مركز الموكلين'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.onAddClient});

  final VoidCallback onAddClient;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.person_search_rounded,
                  size: 34, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'لا يوجد موكلون في هذه القاعدة بعد',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              const Text('ابدأ بإضافة سجل موكل اختباري. لن تظهر ملفات أو جلسات غير موجودة.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAddClient,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة أول موكل'),
              ),
            ],
          ),
        ),
      );
}

class _AvailableWork extends StatelessWidget {
  const _AvailableWork({required this.count, required this.onOpenClients});

  final int count;
  final VoidCallback onOpenClients;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              const Icon(Icons.folder_shared_outlined, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'يوجد $count موكلًا في هذه القاعدة. افتح المركز للبحث والتصفية وإدارة السجلات.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: onOpenClients, child: const Text('فتح المركز')),
            ],
          ),
        ),
      );
}

class _CountError extends StatelessWidget {
  const _CountError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline_rounded),
          title: const Text('تعذر قراءة بيانات هذه القاعدة.'),
          trailing: TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ),
      );
}

String _statusLabel(ClientStatus status) =>
    status == ClientStatus.active ? 'موكل نشط' : 'موكل مؤرشف';

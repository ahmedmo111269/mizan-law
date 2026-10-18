import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../data/errors.dart';
import '../../domain/models.dart';

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({
    required this.controller,
    required this.onAddClient,
    required this.onOpenClient,
    this.initialQuery,
    super.key,
  });

  final AppController controller;
  final String? initialQuery;
  final VoidCallback onAddClient;
  final ValueChanged<String> onOpenClient;

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  late final TextEditingController _searchController =
      TextEditingController(text: widget.initialQuery ?? '');
  Timer? _debounce;
  final List<ClientRecord> _items = <ClientRecord>[];
  ClientStatus _status = ClientStatus.active;
  ClientSort _sort = ClientSort.nameAscending;
  int _page = 0;
  bool _loading = false;
  bool _hasMore = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_scheduleSearch);
    widget.controller.addListener(_onControllerChanged);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant ClientListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.initialQuery != widget.initialQuery &&
        _searchController.text != (widget.initialQuery ?? '')) {
      _searchController.text = widget.initialQuery ?? '';
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _debounce?.cancel();
    _searchController
      ..removeListener(_scheduleSearch)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.isBusy && mounted) _load(reset: true);
  }

  void _scheduleSearch() {
    if (mounted) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) _load(reset: true);
    });
  }

  Future<void> _load({required bool reset}) async {
    if (_loading && !reset) return;
    final request = ++_requestId;
    final page = reset ? 0 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 0;
        _hasMore = false;
      }
    });
    try {
      final result = await widget.controller.clients.listClients(
        query: _searchController.text,
        status: _status,
        sort: _sort,
        page: page,
      );
      if (!mounted || request != _requestId) return;
      setState(() {
        _items.addAll(result.items);
        _page = page;
        _hasMore = result.hasMore;
      });
    } on MizanException catch (error) {
      if (mounted && request == _requestId) {
        setState(() => _error = error.userMessage);
      }
    } catch (_) {
      if (mounted && request == _requestId) {
        setState(() => _error = 'تعذر تحميل الموكلين. أعد المحاولة.');
      }
    } finally {
      if (mounted && request == _requestId) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('الموكلون',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                    const SizedBox(height: 4),
                    Text(
                      'سجلات الموكلين في ${widget.controller.activeWorkspace.name}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                );
                final add = FilledButton.icon(
                  onPressed: widget.onAddClient,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('إضافة موكل'),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[title, const SizedBox(height: 12), add],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    add,
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                labelText: 'بحث في موكلي هذه القاعدة',
                hintText: 'اسم أو هاتف أو بريد إلكتروني',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                ChoiceChip(
                  avatar: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('نشطون'),
                  selected: _status == ClientStatus.active,
                  onSelected: (_) {
                    setState(() => _status = ClientStatus.active);
                    _load(reset: true);
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('مؤرشفون'),
                  selected: _status == ClientStatus.archived,
                  onSelected: (_) {
                    setState(() => _status = ClientStatus.archived);
                    _load(reset: true);
                  },
                ),
                DropdownButton<ClientSort>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(10),
                  items: const <DropdownMenuItem<ClientSort>>[
                    DropdownMenuItem(
                      value: ClientSort.nameAscending,
                      child: Text('الاسم: أ إلى ي'),
                    ),
                    DropdownMenuItem(
                      value: ClientSort.nameDescending,
                      child: Text('الاسم: ي إلى أ'),
                    ),
                    DropdownMenuItem(
                      value: ClientSort.recentlyUpdated,
                      child: Text('الأحدث تعديلًا'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sort = value);
                    _load(reset: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults()),
          ],
        ),
      );

  Widget _buildResults() {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: _MessagePanel(
          icon: Icons.error_outline_rounded,
          title: 'تعذر تحميل الموكلين',
          message: _error!,
          actionLabel: 'إعادة المحاولة',
          onAction: () => _load(reset: true),
        ),
      );
    }
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      final hasQuery = _searchController.text.trim().isNotEmpty;
      final emptyTitle = _status == ClientStatus.active
          ? 'لا يوجد موكلون نشطون في هذه القاعدة'
          : 'لا توجد علاقات موكل مؤرشفة';
      return _MessagePanel(
        icon: hasQuery ? Icons.search_off_rounded : Icons.people_outline_rounded,
        title: hasQuery ? 'لا توجد نتائج' : emptyTitle,
        message: hasQuery
            ? 'لم يظهر تطابق في نطاق هذه القاعدة. جرّب عبارة أخرى.'
            : 'أضف موكلًا أو بدّل إلى قاعدة أخرى. لا توجد سجلات تجريبية مضافة تلقائيًا.',
        actionLabel: hasQuery ? null : 'إضافة موكل',
        onAction: hasQuery ? null : widget.onAddClient,
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final grid = constraints.maxWidth >= 1080;
          if (!grid) {
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == _items.length) return _loadMoreButton();
                return _ClientTile(
                  client: _items[index],
                  onTap: () => widget.onOpenClient(_items[index].engagementId),
                );
              },
            );
          }
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 560,
              mainAxisExtent: 106,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _items.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _items.length) return _loadMoreButton();
              return _ClientTile(
                client: _items[index],
                onTap: () => widget.onOpenClient(_items[index].engagementId),
              );
            },
          );
        },
      ),
    );
  }

  Widget _loadMoreButton() => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: _loading ? null : () => _load(reset: false),
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text(_loading ? 'جارٍ التحميل…' : 'تحميل المزيد'),
          ),
        ),
      );
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.onTap});

  final ClientRecord client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    client.person.kind == PersonKind.organization
                        ? Icons.business_outlined
                        : Icons.person_outline_rounded,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        client.person.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _personSubline(client.person),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusLabel(status: client.status),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_left_rounded),
              ],
            ),
          ),
        ),
      );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final ClientStatus status;

  @override
  Widget build(BuildContext context) {
    final archived = status == ClientStatus.archived;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

String _personSubline(PersonRecord person) {
  final values = <String>[];
  if (person.phone != null) values.add(person.phone!);
  if (person.email != null) values.add(person.email!);
  if (values.isEmpty) return 'بيانات التواصل غير مسجلة';
  return values.join(' · ');
}

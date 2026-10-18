import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'data/office_database.dart';
import 'features/clients/client_list_screen.dart';
import 'features/clients/client_detail_screen.dart';
import 'features/clients/client_editor_screen.dart';
import 'features/home/home_screen.dart';
import 'shared/mizan_theme.dart';

class MizanApp extends StatefulWidget {
  const MizanApp({required this.database, super.key});

  final OfficeDatabase database;

  @override
  State<MizanApp> createState() => _MizanAppState();
}

class _MizanAppState extends State<MizanApp> {
  late final AppController _controller = AppController(widget.database);
  late Future<void> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _controller.initialize();
  }

  void _retryStartup() => setState(() => _startup = _controller.initialize());

  @override
  void dispose() {
    _controller.dispose();
    unawaited(widget.database.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ميزان',
        debugShowCheckedModeBanner: false,
        theme: MizanTheme.light,
        darkTheme: MizanTheme.dark,
        themeMode: ThemeMode.system,
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: FutureBuilder<void>(
          future: _startup,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _StartupErrorScreen(
                onRetry: _retryStartup,
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const _StartupLoadingScreen();
            }
            return AppShell(controller: _controller);
          },
        ),
      );
}

class AppShell extends StatefulWidget {
  const AppShell({required this.controller, super.key});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _clientsScreenVersion = 0;
  String? _clientsInitialQuery;

  void _showClients({String? query}) {
    setState(() {
      _selectedIndex = 1;
      _clientsInitialQuery = query;
      _clientsScreenVersion++;
    });
  }

  void _openClient(String engagementId) {
    unawaited(
      Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ClientDetailScreen(
            controller: widget.controller,
            engagementId: engagementId,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 850;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 20,
              title: const Text(
                'ميزان',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              actions: <Widget>[
                WorkspaceSwitcher(controller: widget.controller),
                const SizedBox(width: 8),
              ],
            ),
            body: Row(
              children: <Widget>[
                if (wide)
                  NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) => setState(() {
                      _selectedIndex = index;
                      if (index == 1) {
                        _clientsInitialQuery = null;
                        _clientsScreenVersion++;
                      }
                    }),
                    labelType: NavigationRailLabelType.all,
                    destinations: const <NavigationRailDestination>[
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: Text('مكتب اليوم'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.people_outline_rounded),
                        selectedIcon: Icon(Icons.people_rounded),
                        label: Text('الموكلون'),
                      ),
                    ],
                  ),
                if (wide) const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: <Widget>[
                      HomeScreen(
                        controller: widget.controller,
                        onOpenClients: _showClients,
                        onOpenClient: _openClient,
                      ),
                      ClientListScreen(
                        key: ValueKey<int>(_clientsScreenVersion),
                        controller: widget.controller,
                        initialQuery: _clientsInitialQuery,
                        onAddClient: () => _addClient(),
                        onOpenClient: _openClient,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) => setState(() {
                      _selectedIndex = index;
                      if (index == 1) {
                        _clientsInitialQuery = null;
                        _clientsScreenVersion++;
                      }
                    }),
                    destinations: const <NavigationDestination>[
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'مكتب اليوم',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.people_outline_rounded),
                        selectedIcon: Icon(Icons.people_rounded),
                        label: 'الموكلون',
                      ),
                    ],
                  ),
          );
        },
      );

  Future<void> _addClient() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClientEditorScreen(controller: widget.controller),
      ),
    );
  }
}

class WorkspaceSwitcher extends StatelessWidget {
  const WorkspaceSwitcher({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => PopupMenuButton<String>(
          tooltip: 'تبديل القاعدة النشطة',
          onSelected: (id) => _select(context, id),
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            for (final workspace in controller.workspaces)
              PopupMenuItem<String>(
                value: workspace.id,
                child: Row(
                  children: <Widget>[
                    if (workspace.id == controller.activeWorkspace.id)
                      const Icon(Icons.check_circle_rounded, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(workspace.name)),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: '__create_workspace__',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.add_rounded),
                title: Text('إنشاء قاعدة مستقلة'),
                dense: true,
              ),
            ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.storage_rounded, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      controller.activeWorkspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _select(BuildContext context, String id) async {
    try {
      if (id == '__create_workspace__') {
        final name = await showDialog<String>(
          context: context,
          builder: (context) => const _CreateWorkspaceDialog(),
        );
        if (name == null || name.trim().isEmpty) return;
        await controller.createWorkspace(name);
      } else {
        await controller.switchWorkspace(id);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح القاعدة أو إنشاؤها. لم تُحذف بيانات أخرى.')),
        );
      }
    }
  }
}

class _CreateWorkspaceDialog extends StatefulWidget {
  const _CreateWorkspaceDialog();

  @override
  State<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<_CreateWorkspaceDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('قاعدة جديدة'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 80,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            labelText: 'اسم القاعدة',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(onPressed: _submit, child: const Text('إنشاء وفتح')),
        ],
      );

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'أدخل اسمًا للقاعدة.');
      return;
    }
    Navigator.pop(context, value);
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جارٍ تجهيز ميزان محليًا…'),
            ],
          ),
        ),
      );
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.storage_rounded, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    'تعذر فتح مساحة البيانات المحلية.',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'لم تُحمّل سجلات الموكلين. أعد المحاولة، أو تحقق من صلاحية مجلد بيانات التطبيق.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

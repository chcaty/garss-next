import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import 'appearance.dart';
import 'results_page.dart';
import 'sources_page.dart';
import 'settings_page.dart';
import 'sync.dart';

// Retain the existing public imports while the pages live in focused modules.
export '../data/reading_order.dart' show diversify;
export 'article_row.dart' show ArticleRow;
export 'reading_page.dart' show ReadingPage;
export 'sources_page.dart' show SourcesPage;
export 'settings_page.dart' show SettingsPage;

const _homeDestinations = [
  (
    label: '榜单',
    icon: Icons.view_agenda_outlined,
    selectedIcon: Icons.view_agenda,
  ),
  (label: '我的收藏', icon: Icons.bookmark_border, selectedIcon: Icons.bookmark),
];

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int tab = 0;
  bool started = false;
  @override
  Widget build(BuildContext context) {
    ref.listen(libraryProvider, (previous, next) {
      if (!started && next.hasValue) {
        started = true;
        if (next.requireValue.message.contains('缓存')) {
          Future.microtask(() => ref.read(libraryProvider.notifier).refresh());
        }
      }
    });
    final library = ref.watch(libraryProvider);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    const titles = ['拾阅', '我的收藏'];
    void select(int value) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => tab = value);
    }

    final content = library.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(semanticsLabel: '正在读取内容'),
            SizedBox(height: 16),
            Text('正在读取内容…'),
          ],
        ),
      ),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 16),
              Text('暂时无法同步内容', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('首次使用需要联网。请检查网络后重试。', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => ref.invalidate(libraryProvider),
                child: const Text('重新同步'),
              ),
            ],
          ),
        ),
      ),
      data: (data) => IndexedStack(
        index: tab,
        children: [
          ResultsPage(library: data),
          ResultsPage(library: data, savedOnly: true),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        title: Text(
          titles[tab],
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          const AppearanceButton(),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == '采集记录') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SyncScreen(),
                  ),
                );
                return;
              }
              final data = library.asData?.value;
              if (data == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Consumer(
                    builder: (context, ref, child) {
                      final current =
                          ref.watch(libraryProvider).asData?.value ?? data;
                      return Scaffold(
                        appBar: AppBar(title: Text(value)),
                        body: value == '来源管理'
                            ? SourcesPage(library: current)
                            : value == '阅读设置'
                            ? SettingsPage(library: current)
                            : const SyncScreen(),
                      );
                    },
                  ),
                ),
              );
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: '来源管理',
                enabled: library.hasValue,
                child: const Text('来源管理'),
              ),
              PopupMenuItem(
                value: '阅读设置',
                enabled: library.hasValue,
                child: const Text('阅读设置'),
              ),
              PopupMenuItem(value: '采集记录', child: Text('采集记录')),
            ],
          ),
          IconButton(
            tooltip: '刷新内容',
            onPressed: library.hasValue && !library.requireValue.syncing
                ? () => ref.read(libraryProvider.notifier).refresh()
                : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: select,
              destinations: [
                for (final destination in _homeDestinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: tab,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final destination in _homeDestinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: Text(destination.label),
                    ),
                ],
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

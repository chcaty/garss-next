import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import 'appearance.dart';
import 'reading_page.dart';
import 'sources_page.dart';
import 'settings_page.dart';
import 'sync.dart';

// Retain the existing public imports while the pages live in focused modules.
export '../data/reading_order.dart' show diversify;
export 'article_row.dart' show ArticleRow;
export 'reading_page.dart' show ReadingPage;
export 'sources_page.dart' show SourcesPage;
export 'settings_page.dart' show SettingsPage;

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
    const titles = ['信息流', '稍后读', '订阅源', '设置'];
    void select(int value) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => tab = value);
    }

    final content = library.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(semanticsLabel: '正在读取文章'),
            SizedBox(height: 16),
            Text('正在读取文章…'),
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
              Text('暂时无法同步文章', style: Theme.of(context).textTheme.titleLarge),
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
          ReadingPage(library: data, onSources: () => select(2)),
          ReadingPage(
            library: data,
            savedOnly: true,
            onSources: () => select(0),
          ),
          SourcesPage(library: data),
          SettingsPage(library: data),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[tab],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          const AppearanceButton(),
          IconButton(
            tooltip: '同步记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (context) => const SyncScreen()),
            ),
            icon: const Icon(Icons.cloud_sync_outlined),
          ),
          IconButton(
            tooltip: '刷新文章',
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
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.view_agenda_outlined),
                  selectedIcon: Icon(Icons.view_agenda),
                  label: '信息流',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark_border),
                  selectedIcon: Icon(Icons.bookmark),
                  label: '稍后读',
                ),
                NavigationDestination(icon: Icon(Icons.rss_feed), label: '订阅源'),
                NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
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
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.view_agenda_outlined),
                    label: Text('信息流'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.bookmark_border),
                    label: Text('稍后读'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.rss_feed),
                    label: Text('订阅源'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.tune),
                    label: Text('设置'),
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

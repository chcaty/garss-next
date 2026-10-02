import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../state/library.dart';
import '../state/appearance.dart';
import 'appearance.dart';
import 'article.dart';
import 'sync.dart';

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
      loading: () => const Center(child: CircularProgressIndicator()),
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

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({
    super.key,
    required this.library,
    this.savedOnly = false,
    required this.onSources,
  });
  final LibraryState library;
  final bool savedOnly;
  final VoidCallback onSources;
  @override
  ConsumerState<ReadingPage> createState() => _ReadingPageState();
}

class _ReadingPageState extends ConsumerState<ReadingPage> {
  final search = TextEditingController();
  String query = '', source = '';
  bool unread = false, balanced = true;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void reset() {
    search.clear();
    setState(() {
      query = '';
      source = '';
      unread = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final colors = Theme.of(context).colorScheme;
    final feeds = library.readingFeeds;
    final canonical = library.catalog.sourceAliases[source] ?? source;
    final selected = feeds.any((feed) => feed.id == canonical) ? canonical : '';
    final hasFilters = query.isNotEmpty || unread || selected.isNotEmpty;
    final filtered = library.visible(
      query: query,
      savedOnly: widget.savedOnly,
      unreadOnly: unread,
      source: widget.savedOnly ? '' : selected,
    );
    final articles = balanced && !widget.savedOnly && selected.isEmpty
        ? diversify(filtered)
        : filtered;
    return RefreshIndicator(
      onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
      child: CustomScrollView(
        key: PageStorageKey('reading-${widget.savedOnly}'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (library.syncing)
                    const LinearProgressIndicator(minHeight: 2),
                  Text(
                    widget.savedOnly ? '把选中的内容，留给安静的阅读。' : '先筛选信息，再进入专注阅读。',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    library.message.isNotEmpty
                        ? library.message
                        : '最近采集 ${articleDate(library.catalog.generatedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: search,
                    onChanged: (value) => setState(() => query = value),
                    decoration: InputDecoration(
                      labelText: widget.savedOnly ? '搜索稍后读' : '搜索文章',
                      hintText: '标题、摘要或来源',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清除搜索',
                              onPressed: () {
                                search.clear();
                                setState(() => query = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('只看未读'),
                        selected: unread,
                        onSelected: (value) => setState(() => unread = value),
                      ),
                      Text(
                        '${articles.length} 篇${widget.savedOnly ? '稍后读' : '文章'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (!widget.savedOnly)
                        PopupMenuButton<bool>(
                          tooltip: '文章排序',
                          initialValue: balanced,
                          onSelected: (value) =>
                              setState(() => balanced = value),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: true, child: Text('按来源轮换')),
                            PopupMenuItem(value: false, child: Text('最新发布')),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  balanced ? '来源轮换' : '最新发布',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      if (hasFilters)
                        TextButton.icon(
                          onPressed: reset,
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 18,
                          ),
                          label: const Text('重置筛选'),
                        ),
                    ],
                  ),
                  if (!widget.savedOnly)
                    DropdownButtonFormField<String>(
                      key: ValueKey(selected),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '阅读来源'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('全部有文章的来源'),
                        ),
                        for (final feed in feeds)
                          DropdownMenuItem(
                            value: feed.id,
                            child: Text(
                              feed.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => source = value ?? ''),
                    ),
                  if (articles.any(
                    (article) => !library.read.contains(article.id),
                  ))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('当前结果全部已读'),
                        onPressed: () {
                          final controller = ref.read(libraryProvider.notifier);
                          final changed = controller.markManyRead(
                            articles.map((article) => article.id),
                          );
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('已将 ${changed.length} 篇文章标为已读'),
                                action: SnackBarAction(
                                  label: '撤销',
                                  onPressed: () =>
                                      controller.markManyUnread(changed),
                                ),
                              ),
                            );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: Divider(height: 1)),
          if (articles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.savedOnly
                          ? Icons.bookmark_border
                          : Icons.auto_stories_outlined,
                      size: 44,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasFilters
                          ? '没有匹配的文章'
                          : widget.savedOnly
                          ? '这里留给想再读的文章'
                          : '暂时没有可读文章',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasFilters
                          ? '试试其他关键词，或重置筛选。'
                          : widget.savedOnly
                          ? '点击文章右侧的书签图标，加入稍后读。'
                          : '下拉刷新文章，或到订阅源选择关注。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.tonal(
                      onPressed: hasFilters ? reset : widget.onSources,
                      child: Text(
                        hasFilters
                            ? '重置筛选'
                            : widget.savedOnly
                            ? '去阅读文章'
                            : '选择来源',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index.isOdd) {
                  return const Divider(height: 1, indent: 20, endIndent: 20);
                }
                final article = articles[index ~/ 2];
                return ArticleRow(
                  key: ValueKey(article.id),
                  article: article,
                  library: library,
                  queue: articles,
                );
              }, childCount: articles.length * 2 - 1),
            ),
        ],
      ),
    );
  }
}

List<Article> diversify(List<Article> articles) {
  final groups = <String, List<Article>>{};
  for (final article in articles) {
    groups.putIfAbsent(article.sourceId, () => []).add(article);
  }
  final result = <Article>[];
  for (var round = 0; result.length < articles.length; round++) {
    final batch = [
      for (final group in groups.values)
        if (round < group.length) group[round],
    ]..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    result.addAll(batch);
  }
  return result;
}

class ArticleRow extends ConsumerWidget {
  const ArticleRow({
    super.key,
    required this.article,
    required this.library,
    required this.queue,
  });
  final Article article;
  final LibraryState library;
  final List<Article> queue;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final saved = library.saved.containsKey(article.id),
        read = library.read.contains(article.id);
    return InkWell(
      onTap: () {
        ref.read(libraryProvider.notifier).markRead(article.id);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => ArticleScreen(article: article, queue: queue),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${article.sourceTitle} · ${article.dateInferred ? '首次发现 ' : ''}${articleDate(article.publishedAt)}${read ? ' · 已读' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    style: TextStyle(
                      fontSize: 16 * library.fontScale,
                      height: 1.6,
                      fontWeight: read ? FontWeight.w500 : FontWeight.w600,
                      color: read ? colors.onSurfaceVariant : colors.onSurface,
                    ),
                  ),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      article.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: saved ? '移出稍后读' : '加入稍后读',
              onPressed: () =>
                  ref.read(libraryProvider.notifier).toggleSaved(article),
              icon: Icon(
                saved ? Icons.bookmark : Icons.bookmark_border,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key, required this.library});
  final LibraryState library;
  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  final search = TextEditingController();
  String query = '', filter = 'all', category = 'all';
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library, colors = Theme.of(context).colorScheme;
    final counts = library.articleCounts;
    final categories =
        library.catalog.feeds
            .map((feed) => feed.category)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final feeds = library.catalog.feeds
        .where(
          (feed) =>
              (category == 'all' || feed.category == category) &&
              ('${feed.title} ${feed.description} ${feed.url} ${feed.category}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase())) &&
              (filter == 'all' ||
                  filter == 'ok' && feed.enabled && feed.status == 'ok' ||
                  filter == 'error' && feed.enabled && feed.status == 'error' ||
                  filter == 'followed' &&
                      feed.enabled &&
                      !library.hidden.contains(feed.id) ||
                  filter == 'empty' && (counts[feed.id] ?? 0) == 0),
        )
        .toList();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('整理你的信息入口', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '关注只影响本机阅读。公共采集配置在网页订阅源中管理。',
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.7),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://chcaty.github.io/garss-next/sources.html',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('管理公共订阅与发现出处'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: search,
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    labelText: '搜索来源',
                    hintText: '名称、分类或地址',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in const {
                      'all': '全部',
                      'ok': '采集正常',
                      'error': '采集异常',
                      'followed': '已关注',
                      'empty': '暂无文章',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: filter == entry.key,
                        onSelected: (_) => setState(() => filter = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '分类'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('全部分类')),
                    for (final value in categories)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) =>
                      setState(() => category = value ?? 'all'),
                ),
                const SizedBox(height: 12),
                Text(
                  '${feeds.length} 个匹配 · ${library.readingFeeds.length} 个来源有可读文章',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (feeds.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('没有找到来源，试试其他关键词或筛选。'),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index.isOdd) {
                return const Divider(height: 1, indent: 20, endIndent: 20);
              }
              final feed = feeds[index ~/ 2];
              return SwitchListTile(
                key: ValueKey(feed.id),
                title: Text(feed.title),
                subtitle: Text(
                  '${feed.category} · ${counts[feed.id] ?? 0} 篇文章 · ${!feed.enabled
                      ? '公共采集已停用'
                      : feed.status == 'error'
                      ? '采集异常'
                      : '采集正常'}',
                  style: TextStyle(
                    color: feed.status == 'error' && feed.enabled
                        ? colors.error
                        : colors.onSurfaceVariant,
                  ),
                ),
                value: feed.enabled && !library.hidden.contains(feed.id),
                onChanged: feed.enabled
                    ? (enabled) => ref
                          .read(libraryProvider.notifier)
                          .follow(feed.id, enabled)
                    : null,
              );
            }, childCount: feeds.length * 2 - 1),
          ),
      ],
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, required this.library});
  final LibraryState library;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final appearance = ref.watch(appearanceProvider).value ?? ThemeMode.system;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('阅读与外观', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('外观'),
          subtitle: Text(appearanceLabel(appearance)),
          trailing: const AppearanceButton(),
        ),
        const Divider(height: 32),
        Text('文章字号', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '当前字号 ${(library.fontScale * 100).round()}%',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        Slider(
          value: library.fontScale,
          min: 1,
          max: 1.4,
          divisions: 4,
          label: '${(library.fontScale * 100).round()}%',
          onChanged: (value) =>
              ref.read(libraryProvider.notifier).setFontScale(value),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: colors.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '阅读，从一篇好文章开始',
                style: TextStyle(
                  fontSize: 18 * library.fontScale,
                  fontWeight: FontWeight.w600,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '这是字号预览。选好信息后，按自己的节奏阅读。',
                style: TextStyle(
                  fontSize: 14 * library.fontScale,
                  height: 1.8,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('专注阅读显示图片'),
          subtitle: const Text('图片来自原站，关闭可节省流量。'),
          value: library.showImages,
          onChanged: (value) =>
              ref.read(libraryProvider.notifier).setImages(value),
        ),
        const Divider(height: 32),
        Text('本机阅读记录', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Text(
          '${library.saved.length} 篇稍后读 · ${library.read.length} 篇已读',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Text(
          '稍后读、摘要、已读和关注保存在本机。原文和远程图片需要联网。',
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.8),
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_sync_outlined),
          title: const Text('同步记录'),
          subtitle: const Text('最近采集、异常来源与历史批次'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (context) => const SyncScreen()),
          ),
        ),
        const Divider(height: 32),
        const Text(
          '拾阅 · Android 预览版 0.2.0',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          '数据由 GitHub 定时采集并发布。手机只同步文章快照，文章离开目录后，稍后读仍然保留。',
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.8),
        ),
      ],
    );
  }
}

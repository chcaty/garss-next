import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import '../data/reading_filter.dart';
import '../data/reading_order.dart';
import 'article.dart';
import 'article_row.dart';
import 'reading_filters.dart';
import 'reading_source_sheet.dart';

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
  String query = '', source = '', category = '';
  ReadingPeriod period = ReadingPeriod.all;
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
      category = '';
      period = ReadingPeriod.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    final colors = Theme.of(context).colorScheme;
    final feeds = library.readingFeeds;
    final unreadBySource = library.unreadCounts;
    final canonical = library.catalog.sourceAliases[source] ?? source;
    final selected = feeds.any((feed) => feed.id == canonical) ? canonical : '';
    final categories =
        widget.savedOnly
              ? library.savedCategories
              : feeds
                    .map((feed) => feed.category)
                    .where((value) => value.isNotEmpty)
                    .toSet()
                    .toList()
          ..sort();
    final hasFilters =
        query.isNotEmpty ||
        unread ||
        selected.isNotEmpty ||
        category.isNotEmpty ||
        period != ReadingPeriod.all;
    final filtered = library.visible(
      query: query,
      savedOnly: widget.savedOnly,
      unreadOnly: unread,
      source: widget.savedOnly ? '' : selected,
      category: category,
      period: period,
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
                        : '最近采集（北京时间）${articleDate(library.catalog.generatedAt)}',
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
                      ActionChip(
                        avatar: const Icon(Icons.filter_list, size: 18),
                        label: Text(
                          category.isEmpty && period == ReadingPeriod.all
                              ? '分类与时间'
                              : [
                                  if (category.isNotEmpty) category,
                                  if (period != ReadingPeriod.all)
                                    periodLabel(period),
                                ].join(' · '),
                        ),
                        onPressed: () async {
                          final selection =
                              await showModalBottomSheet<ReadingSelection>(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                showDragHandle: true,
                                constraints: const BoxConstraints(
                                  maxWidth: 640,
                                ),
                                builder: (context) => ReadingFilterSheet(
                                  categories: categories,
                                  selection: ReadingSelection(
                                    category: category,
                                    period: period,
                                  ),
                                ),
                              );
                          if (mounted && selection != null) {
                            setState(() {
                              category = selection.category;
                              period = selection.period;
                            });
                          }
                        },
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.rss_feed, size: 18),
                        label: Text(
                          selected.isEmpty
                              ? '选择阅读来源'
                              : feeds
                                    .firstWhere((feed) => feed.id == selected)
                                    .title,
                          maxLines: 2,
                        ),
                        onPressed: () async {
                          final value = await showModalBottomSheet<String>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            showDragHandle: true,
                            constraints: const BoxConstraints(maxWidth: 640),
                            builder: (context) => ReadingSourceSheet(
                              feeds: feeds,
                              selected: selected,
                              unread: unreadBySource,
                            ),
                          );
                          if (mounted && value != null) {
                            setState(() => source = value);
                          }
                        },
                      ),
                    ),
                  if (articles.any(
                    (article) => !library.read.contains(article.id),
                  ))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.done_all, size: 18),
                        label: Text('当前结果 ${filtered.length} 篇全部已读'),
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

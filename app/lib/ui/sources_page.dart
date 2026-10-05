import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';

import 'package:url_launcher/url_launcher.dart';

import '../data/sync_report.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key, required this.library});
  final LibraryState library;
  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  final search = TextEditingController();
  String query = '', filter = 'all', category = 'all';
  bool followedOnly = false;
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
              (!followedOnly ||
                  feed.enabled && !library.hidden.contains(feed.id)) &&
              (filter == 'all' ||
                  filter == 'ok' && feed.effectiveStatus == 'active' ||
                  filter == 'error' && feed.effectiveStatus == 'error' ||
                  filter == 'archived' && feed.effectiveStatus == 'archived' ||
                  filter == 'disabled' && feed.effectiveStatus == 'disabled' ||
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
                Text('本机关注', style: Theme.of(context).textTheme.titleLarge),
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
                    FilterChip(
                      label: const Text('只看本机关注'),
                      selected: followedOnly,
                      onSelected: (value) =>
                          setState(() => followedOnly = value),
                    ),
                    for (final entry in const {
                      'all': '全部',
                      'ok': '采集正常',
                      'error': '采集异常',
                      'archived': '自动归档',
                      'disabled': '公共停用',
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('没有匹配的来源。'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      search.clear();
                      setState(() {
                        query = '';
                        filter = 'all';
                        category = 'all';
                        followedOnly = false;
                      });
                    },
                    child: const Text('清除来源筛选'),
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
              final feed = feeds[index ~/ 2];
              return SwitchListTile(
                key: ValueKey(feed.id),
                title: Text(feed.title),
                subtitle: Text(
                  '${feed.category} · ${counts[feed.id] ?? 0} 篇文章 · ${collectionStatusLabel(feed.effectiveStatus)}${feed.enabled && library.hidden.contains(feed.id) ? ' · 本机未关注' : ''}',
                  style: TextStyle(
                    color: feed.effectiveStatus == 'error'
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

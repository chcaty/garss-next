import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/board.dart';
import '../data/models.dart';
import '../state/library.dart';
import 'article.dart';
import 'reading_actions.dart';
import 'image_headers.dart';

class ResultsPage extends ConsumerStatefulWidget {
  const ResultsPage({super.key, required this.library, this.savedOnly = false});
  final LibraryState library;
  final bool savedOnly;
  @override
  ConsumerState<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends ConsumerState<ResultsPage> {
  final search = TextEditingController();
  String query = '', source = '', category = '', kind = 'all';
  String view = 'boards';
  bool onlyNew = false, compact = false;
  int limit = 12;
  final expanded = <String, int>{};
  @override
  void didUpdateWidget(ResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final available = resultGroups(widget.library, savedOnly: widget.savedOnly);
    if (source.isNotEmpty &&
        !available.any((group) => group.feed.id == source)) {
      source = '';
    }
    if (category.isNotEmpty &&
        !available.any((group) => group.feed.category == category)) {
      category = '';
    }
  }

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
      category = '';
      kind = 'all';
      onlyNew = false;
      limit = 12;
    });
  }

  Future<void> open(Article article) async {
    ref.read(libraryProvider.notifier).markRead(article.id);
    final launched = await launchUrl(
      Uri.parse(article.url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开原文，请检查设备浏览器')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library, colors = Theme.of(context).colorScheme;
    final groups = resultGroups(
      library,
      savedOnly: widget.savedOnly,
      query: query,
      source: source,
      category: category,
      kind: kind,
      onlyNew: !widget.savedOnly && onlyNew,
    );
    final available = resultGroups(library, savedOnly: widget.savedOnly);
    final visibleSources = widget.savedOnly || view == 'boards'
        ? available
        : available.where((group) => isChronologicalFeed(group.feed)).toList();
    final categories =
        visibleSources.map((group) => group.feed.category).toSet().toList()
          ..sort();
    final sources = {
      for (final group in visibleSources) group.feed.id: group.feed.title,
    };
    final entries = feedEntries(groups, includeRankedSources: widget.savedOnly);
    final count = {
      for (final group in groups)
        for (final article in group.articles) article.id,
    }.length;
    final fresh = {
      for (final group in groups)
        for (final article in group.articles)
          if (group.newIds.contains(article.id)) article.id,
    }.length;
    final filtered =
        query.isNotEmpty ||
        source.isNotEmpty ||
        category.isNotEmpty ||
        kind != 'all' ||
        onlyNew;
    final known = groups.any((group) => group.feed.baselineKnown == true);
    return RefreshIndicator(
      onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
      child: ListView(
        key: PageStorageKey('results-${widget.savedOnly}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (library.syncing) const LinearProgressIndicator(),
          Text(
            '北京时间 ${articleDate(library.catalog.generatedAt)} 更新',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          if (library.message.isNotEmpty && library.message != '已同步最新内容') ...[
            const SizedBox(height: 4),
            Text(
              library.message,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '$count 条内容 · ${groups.length} 个榜单${widget.savedOnly ? '' : ' · 新增 ${known ? fresh : '—'}'}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'boards', label: Text('榜单')),
              ButtonSegment(value: 'feed', label: Text('信息流')),
            ],
            selected: {view},
            onSelectionChanged: (selection) => setState(() {
              view = selection.first;
              if (selection.first == 'feed' &&
                  !widget.savedOnly &&
                  !available.any(
                    (group) =>
                        group.feed.id == source &&
                        isChronologicalFeed(group.feed),
                  )) {
                source = '';
              }
              limit = 12;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: search,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              labelText: '搜索内容',
              floatingLabelBehavior: FloatingLabelBehavior.never,
              hintText: '标题、摘要或榜单',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            onChanged: (value) => setState(() {
              query = value;
              limit = 12;
            }),
          ),
          const SizedBox(height: 4),
          ExpansionTile(
            key: PageStorageKey('result-filters-${widget.savedOnly}'),
            tilePadding: EdgeInsets.zero,
            dense: true,
            minTileHeight: 48,
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('筛选', style: TextStyle(fontSize: 14)),
            subtitle: source.isEmpty && category.isEmpty && kind == 'all'
                ? null
                : Text(
                    [
                      if (source.isNotEmpty) sources[source] ?? source,
                      if (category.isNotEmpty) category,
                      if (kind != 'all') contentLabels[kind] ?? kind,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('source-${widget.savedOnly}-$source'),
                initialValue: source,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '榜单'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部榜单')),
                  for (final entry in sources.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() {
                  source = value ?? '';
                  limit = 12;
                }),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {'all': '全部类型', ...contentLabels}.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: kind == entry.key,
                      onSelected: (_) => setState(() {
                        kind = entry.key;
                        limit = 12;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('category-${widget.savedOnly}-$category'),
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分类'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部分类')),
                  for (final item in categories.where(
                    (value) => value.isNotEmpty,
                  ))
                    DropdownMenuItem(value: item, child: Text(item)),
                ],
                onChanged: (value) => setState(() {
                  category = value ?? '';
                  limit = 12;
                }),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              if (!widget.savedOnly)
                FilterChip(
                  label: const Text('只看新增', style: TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: onlyNew,
                  onSelected: (value) => setState(() {
                    onlyNew = value;
                    limit = 12;
                  }),
                ),
              FilterChip(
                label: const Text('紧凑视图', style: TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                selected: compact,
                onSelected: (value) => setState(() => compact = value),
              ),
              if (filtered)
                TextButton(onPressed: reset, child: const Text('清除筛选')),
            ],
          ),
          if (view == 'feed' && entries.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('最新更新', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final entry in entries.take(limit))
              ResultTile(
                key: ValueKey(entry.article.id),
                article: entry.article,
                source: entry.feed.id,
                sourceTitle: entry.feed.title,
                sourceCategory: entry.feed.category,
                compact: compact,
                fresh: entry.isNew,
                library: library,
                onOpen: () => open(entry.article),
              ),
          ],
          if (view == 'boards')
            for (final group in groups.take(limit)) ...[
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      group.feed.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${group.articles.length} 条${group.newIds.isEmpty ? '' : ' · 新增 ${group.articles.where((article) => group.newIds.contains(article.id)).length}'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${group.feed.category} · ${widget.savedOnly ? '本机收藏' : collectionCondition(group.feed)}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const Divider(height: 20),
              for (final article in group.articles.take(
                expanded[group.feed.id] ?? 6,
              ))
                ResultTile(
                  key: ValueKey('${group.feed.id}-${article.id}'),
                  article: article,
                  source: group.feed.id,
                  sourceTitle: group.feed.title,
                  sourceCategory: group.feed.category,
                  compact: compact,
                  fresh: group.newIds.contains(article.id),
                  library: library,
                  onOpen: () => open(article),
                ),
              if (group.articles.length > (expanded[group.feed.id] ?? 6))
                OutlinedButton(
                  onPressed: () => setState(
                    () => expanded[group.feed.id] =
                        (expanded[group.feed.id] ?? 6) + 12,
                  ),
                  child: Text(
                    '展开更多 · 还有 ${group.articles.length - (expanded[group.feed.id] ?? 6)} 条',
                  ),
                ),
            ],
          if (view == 'boards' && groups.isEmpty ||
              view == 'feed' && entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Text(
                    widget.savedOnly && !filtered ? '暂无收藏' : '没有符合条件的内容',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.savedOnly && !filtered
                        ? '收藏的内容会显示在这里。'
                        : '调整筛选条件或清除筛选。',
                  ),
                  if (filtered)
                    TextButton(onPressed: reset, child: const Text('清除筛选')),
                ],
              ),
            ),
          if (view == 'feed' && entries.length > limit)
            OutlinedButton(
              onPressed: () => setState(() => limit += 12),
              child: const Text('显示更多内容'),
            ),
          if (view == 'boards' && groups.length > limit)
            OutlinedButton(
              onPressed: () => setState(() => limit += 12),
              child: const Text('显示更多榜单'),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class ResultTile extends ConsumerWidget {
  const ResultTile({
    super.key,
    required this.article,
    required this.source,
    required this.sourceTitle,
    required this.sourceCategory,
    required this.compact,
    required this.fresh,
    required this.library,
    required this.onOpen,
  });
  final Article article;
  final String source, sourceTitle, sourceCategory;
  final bool compact, fresh;
  final LibraryState library;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme,
        values = article.observation(source);
    final amber = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xfff0cc8b)
        : const Color(0xff946418);
    final metrics = <String>[];
    for (final entry in {
      'stars': 'Star',
      'stars_today': '今日新增 Star',
      'views': '播放',
      'likes': '赞',
      'replies': '回复',
      'heat': '热度',
      'rating': '评分',
      'votes': '评分人数',
      'score': '分数',
      'answers': '回答',
    }.entries) {
      final value = values[entry.key];
      if (value is num && (value >= 0 || entry.key == 'score')) {
        final label = entry.key == 'views' && article.contentType != 'video'
            ? '阅读'
            : entry.value;
        metrics.add('$label ${compactNumber(value)}');
      }
    }
    if (values['duration'] != null && article.contentType == 'video') {
      metrics.add('时长 ${values['duration']}');
    }
    final metadata = [
      for (final key in ['author', 'language', 'label', 'code'])
        if (values[key] != null && '${values[key]}'.isNotEmpty)
          '${values[key]}',
      ...metrics,
    ];
    final metadataStyle = TextStyle(
      fontSize: 11.5,
      height: 1.5,
      color: colors.onSurfaceVariant,
    );
    final rank = values['rank'];
    final avatar = article.contentType == 'repository';
    final portrait = article.contentType == 'item';
    final imageWidth = avatar
        ? 32.0
        : portrait
        ? 56.0
        : 76.0;
    final imageHeight = avatar
        ? 32.0
        : portrait
        ? 76.0
        : 48.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: fresh ? amber : colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InkWell(
              onTap: onOpen,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  compact ? 12 : 14,
                  44,
                  compact ? 12 : 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rank is num && rank > 0) ...[
                      SizedBox(
                        width: 18,
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (article.imageUrl.isNotEmpty && library.showImages) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(avatar ? 16 : 8),
                        child: ColoredBox(
                          color: colors.primaryContainer,
                          child: SizedBox(
                            width: imageWidth,
                            height: imageHeight,
                            child: Image.network(
                              article.imageUrl,
                              key: ValueKey(
                                '${article.imageUrl}-${library.syncing}',
                              ),
                              headers: imageRequestHeaders(article.imageUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) => Tooltip(
                                message: '图片暂时无法加载，下拉刷新可重试',
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                contentLabels[article.contentType] ?? '条目',
                                style: metadataStyle,
                              ),
                              Text(
                                sourceTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metadataStyle,
                              ),
                              if (sourceCategory.isNotEmpty)
                                Text(sourceCategory, style: metadataStyle),
                              if (fresh)
                                Text(
                                  '新增',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: amber,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            article.title,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                              fontSize: 14.5 * library.fontScale,
                            ),
                          ),
                          if (!compact && article.summary.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              article.summary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.6,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 10,
                              runSpacing: 3,
                              children: [
                                for (final value in metadata)
                                  Text(value, style: metadataStyle),
                              ],
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            '${article.dateInferred ? '首次发现' : '发布'} ${articleDate(article.publishedAt)}',
                            style: metadataStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                tooltip: library.saved.containsKey(article.id)
                    ? '移出收藏'
                    : '加入收藏',
                onPressed: () => toggleSavedWithFeedback(context, ref, article),
                icon: Icon(
                  library.saved.containsKey(article.id)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  size: 20,
                  color: library.saved.containsKey(article.id)
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

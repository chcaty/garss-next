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
    final count = {
      for (final group in groups)
        for (final article in group.articles) article.id,
    }.length;
    final fresh = {
      for (final group in groups)
        for (final article in group.articles)
          if (group.newIds.contains(article.id)) article.id,
    }.length;
    final available = resultGroups(library, savedOnly: widget.savedOnly);
    final categories =
        available.map((group) => group.feed.category).toSet().toList()..sort();
    final sources = {
      for (final group in available) group.feed.id: group.feed.title,
    };
    final highlights = groups
        .where(
          (group) => group.feed.status == 'ok' && group.articles.isNotEmpty,
        )
        .take(4)
        .toList();
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
            '$count 条内容 · ${groups.length} 个来源${widget.savedOnly ? '' : ' · 较上次采集新增 ${known ? fresh : '—'}'}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: search,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              labelText: '搜索内容',
              floatingLabelBehavior: FloatingLabelBehavior.never,
              hintText: '标题、摘要或来源',
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
            title: const Text('来源、分类与类型', style: TextStyle(fontSize: 14)),
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
                decoration: const InputDecoration(labelText: '来源'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部来源')),
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
          if (!widget.savedOnly && highlights.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('当前看点', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ResultHighlights(groups: highlights, onOpen: open),
          ],
          for (final group in groups.take(limit)) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    group.feed.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${group.articles.length} 条',
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
            const SizedBox(height: 3),
            Text(
              '最近成功 ${group.feed.collectedAt == null ? '暂无记录' : articleDate(group.feed.collectedAt!)}',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            const Divider(height: 20),
            for (final article in group.articles.take(
              expanded[group.feed.id] ?? 6,
            ))
              ResultTile(
                key: ValueKey('${group.feed.id}-${article.id}'),
                article: article,
                source: group.feed.id,
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
                child: const Text('展开更多'),
              ),
          ],
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Text(
                    widget.savedOnly && !filtered ? '还没有收藏' : '没有匹配的内容',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.savedOnly && !filtered
                        ? '点击卡片旁的书签，把想看的内容留下。'
                        : '试试其他关键词、来源或内容类型。',
                  ),
                  if (filtered)
                    TextButton(onPressed: reset, child: const Text('清除筛选')),
                ],
              ),
            ),
          if (groups.length > limit)
            OutlinedButton(
              onPressed: () => setState(() => limit += 12),
              child: const Text('显示更多来源'),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class ResultHighlights extends StatelessWidget {
  const ResultHighlights({
    super.key,
    required this.groups,
    required this.onOpen,
  });
  final List<ResultGroup> groups;
  final Future<void> Function(Article) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(1) > 1.4
            ? 1
            : constraints.maxWidth >= 600
            ? 4
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final group in groups.take(columns == 4 ? 4 : 2))
              SizedBox(
                width: width,
                child: Material(
                  color: colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onOpen(group.articles.first),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.feed.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 5),
                          SizedBox(
                            height:
                                MediaQuery.textScalerOf(context).scale(13) * 3,
                            child: Text(
                              group.articles.first.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            contentLabels[group.articles.first.contentType] ??
                                '条目',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class ResultTile extends ConsumerWidget {
  const ResultTile({
    super.key,
    required this.article,
    required this.source,
    required this.compact,
    required this.fresh,
    required this.library,
    required this.onOpen,
  });
  final Article article;
  final String source;
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

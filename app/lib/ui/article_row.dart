import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/library.dart';
import '../data/models.dart';
import 'article.dart';
import 'reading_actions.dart';

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
              onPressed: () => toggleSavedWithFeedback(context, ref, article),
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

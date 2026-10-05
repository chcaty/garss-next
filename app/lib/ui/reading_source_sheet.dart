import 'package:flutter/material.dart';

import '../data/models.dart';

class ReadingSourceSheet extends StatefulWidget {
  const ReadingSourceSheet({
    super.key,
    required this.feeds,
    required this.selected,
    required this.unread,
  });
  final List<Feed> feeds;
  final String selected;
  final Map<String, int> unread;
  @override
  State<ReadingSourceSheet> createState() => _ReadingSourceSheetState();
}

class _ReadingSourceSheetState extends State<ReadingSourceSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final feeds = widget.feeds
        .where(
          (feed) => '${feed.title} ${feed.category}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('阅读来源', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: '搜索来源或分类',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('全部有文章的来源'),
                    selected: widget.selected.isEmpty,
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  if (feeds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('没有匹配的来源，试试其他关键词。'),
                    ),
                  for (final feed in feeds)
                    ListTile(
                      key: ValueKey(feed.id),
                      title: Text(feed.title),
                      subtitle: Text(
                        '${feed.category} · ${widget.unread[feed.id] ?? 0} 未读',
                      ),
                      selected: widget.selected == feed.id,
                      onTap: () => Navigator.pop(context, feed.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

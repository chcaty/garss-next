import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reading_filter.dart';

String periodLabel(ReadingPeriod period) => switch (period) {
  ReadingPeriod.all => '全部时间',
  ReadingPeriod.today => '今天',
  ReadingPeriod.week => '近 7 天',
};

class ReadingFilterSheet extends ConsumerStatefulWidget {
  const ReadingFilterSheet({
    super.key,
    required this.categories,
    required this.selection,
  });
  final List<String> categories;
  final ReadingSelection selection;
  @override
  ConsumerState<ReadingFilterSheet> createState() => _ReadingFilterSheetState();
}

class _ReadingFilterSheetState extends ConsumerState<ReadingFilterSheet> {
  late String category;
  late ReadingPeriod period;
  @override
  void initState() {
    super.initState();
    category = widget.categories.contains(widget.selection.category)
        ? widget.selection.category
        : '';
    period = widget.selection.period;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('筛选文章', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              key: ValueKey(category),
              initialValue: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '文章分类'),
              items: [
                const DropdownMenuItem(value: '', child: Text('全部分类')),
                for (final item in widget.categories)
                  DropdownMenuItem(value: item, child: Text(item)),
              ],
              onChanged: (value) => setState(() => category = value ?? ''),
            ),
            const SizedBox(height: 24),
            Text('发布时间', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final value in ReadingPeriod.values)
                  ChoiceChip(
                    label: Text(periodLabel(value)),
                    selected: period == value,
                    onSelected: (_) => setState(() => period = value),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '按北京时间计算。缺少原始日期的热榜按首次发现时间筛选。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    ReadingSelection(category: category, period: period),
                  ),
                  child: const Text('应用筛选'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    category = '';
                    period = ReadingPeriod.all;
                  }),
                  child: const Text('清除分类与时间'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

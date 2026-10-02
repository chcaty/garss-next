import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/library.dart';
import '../data/models.dart';
import '../state/sync.dart';
import '../data/sync_report.dart';
import 'appearance.dart';

const actionLogs = 'https://github.com/chcaty/garss-next/actions';
String syncDate(DateTime? value) {
  if (value == null) return '暂无记录';
  final time = value.toUtc().add(const Duration(hours: 8));
  return '${time.year}/${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

Future<void> openLogs(BuildContext context, [String value = actionLogs]) async {
  final opened = await launchUrl(
    Uri.parse(value),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开浏览器，请稍后重试')));
  }
}

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});
  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool started = false;
  String filter = 'error';
  int limit = 20;
  @override
  Widget build(BuildContext context) {
    ref.listen(syncProvider, (before, next) {
      if (!started && next.hasValue) {
        started = true;
        if (next.requireValue.message.contains('缓存')) {
          Future.microtask(() => ref.read(syncProvider.notifier).refresh());
        }
      }
    });
    final data = ref.watch(syncProvider),
        library = ref.watch(libraryProvider).asData?.value;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步记录'),
        actions: [
          const AppearanceButton(),
          IconButton(
            tooltip: '刷新同步状态',
            onPressed: () => data.hasValue
                ? ref.read(syncProvider.notifier).refresh()
                : ref.invalidate(syncProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: data.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      '同步记录暂时无法加载',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '文章缓存和稍后读仍可使用。检查网络后重试，或查看采集日志。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => ref.invalidate(syncProvider),
                      child: const Text('重新加载'),
                    ),
                    TextButton(
                      onPressed: () => openLogs(context),
                      child: const Text('打开采集日志'),
                    ),
                  ],
                ),
              ),
              data: (state) {
                final report = state.report;
                final entries = report.sources.entries
                    .where(
                      (entry) =>
                          filter == 'all' || entry.value.status == filter,
                    )
                    .toList();
                final names = {
                  for (final feed in library?.catalog.feeds ?? <Feed>[])
                    feed.id: feed.title,
                };
                return RefreshIndicator(
                  onRefresh: () => ref.read(syncProvider.notifier).refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (state.refreshing) const LinearProgressIndicator(),
                      if (state.message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            state.message,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      Text(
                        '最近已发布采集',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '北京时间 ${syncDate(report.generatedAt)}',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '每天 06:00、13:00、17:00、22:00（北京时间）计划采集。实际启动可能受 GitHub 排队影响。',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '手机刷新只下载已发布 JSON。运行中或未发布的失败任务，请查看采集日志。',
                        style: TextStyle(height: 1.8),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => openLogs(context),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('采集任务与日志'),
                      ),
                      const Divider(height: 40),
                      Text(
                        '来源采集情况',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final entry in const {
                            'error': '采集异常',
                            'active': '采集正常',
                            'archived': '已归档',
                            'all': '全部',
                          }.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: filter == entry.key,
                              onSelected: (_) => setState(() {
                                filter = entry.key;
                                limit = 20;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${entries.length} 个来源',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('没有匹配的来源。'),
                        ),
                      for (final entry in entries.take(limit))
                        SourceSyncRow(
                          title: names[entry.key] ?? entry.key,
                          state: entry.value,
                        ),
                      if (entries.length > limit)
                        TextButton(
                          onPressed: () => setState(() => limit += 20),
                          child: const Text('显示更多来源'),
                        ),
                      const Divider(height: 40),
                      Text(
                        '采集批次',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '保留最近 30 次已发布记录。成功包含正常但没有新文章的来源。',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.8,
                        ),
                      ),
                      if (report.runs.isEmpty) const Text('历史记录将在新版采集发布后积累。'),
                      for (final run in report.runs)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                syncDate(run.generatedAt),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '检查 ${run.checked} · 正常 ${run.succeeded} · 异常 ${run.failed}\n${run.articleCount} 篇去重文章 · 耗时 ${run.durationSeconds} 秒',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  height: 1.8,
                                ),
                              ),
                              if (RegExp(r'^\d+$').hasMatch(run.workflowRunId))
                                TextButton.icon(
                                  onPressed: () => openLogs(
                                    context,
                                    '$actionLogs/runs/${run.workflowRunId}',
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: const Text('本次日志'),
                                ),
                              const Divider(),
                            ],
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => openLogs(
                          context,
                          'https://chcaty.github.io/garss-next/sources.html#provenance',
                        ),
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('查看发现出处'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class SourceSyncRow extends StatelessWidget {
  const SourceSyncRow({super.key, required this.title, required this.state});
  final String title;
  final SourceHealth state;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(
        '最近检查 ${syncDate(state.lastCheckedAt)}',
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.error.isNotEmpty)
                Text(
                  state.error,
                  style: TextStyle(color: colors.error, height: 1.7),
                ),
              const SizedBox(height: 8),
              Text(
                '最近成功 ${syncDate(state.lastSuccessAt)} · 连续失败 ${state.failures} 次',
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

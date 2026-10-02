import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/models.dart';
import '../state/library.dart';
import 'appearance.dart';

String articleDate(DateTime time) {
  final local = time.toLocal();
  return '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class ArticleImage extends StatelessWidget {
  const ArticleImage({super.key, required this.url, this.height = 180});
  final String url;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      cacheWidth: 900,
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : SizedBox(
              height: height,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
    ),
  );
}

class ArticleScreen extends ConsumerStatefulWidget {
  const ArticleScreen({
    super.key,
    required this.article,
    this.queue = const [],
  });
  final Article article;
  final List<Article> queue;
  @override
  ConsumerState<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends ConsumerState<ArticleScreen> {
  late List<Article> queue;
  late int index;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    queue = widget.queue.isEmpty ? [widget.article] : List.of(widget.queue);
    index = queue.indexWhere((item) => item.id == widget.article.id);
    if (index < 0) {
      queue = [widget.article, ...queue];
      index = 0;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void move(int next) {
    ref.read(libraryProvider.notifier).markRead(queue[next].id);
    setState(() => index = next);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider).requireValue;
    final article = queue[index];
    final colors = Theme.of(context).colorScheme;
    final saved = library.saved.containsKey(article.id);
    return Scaffold(
      appBar: AppBar(
        title: const Text('专注阅读'),
        actions: [
          const AppearanceButton(),
          IconButton(
            tooltip: saved ? '移出稍后读' : '加入稍后读',
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () =>
                ref.read(libraryProvider.notifier).toggleSaved(article),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '${article.sourceTitle} · ${article.dateInferred ? '首次发现 ' : ''}${articleDate(article.publishedAt)}',
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.7),
                ),
                const SizedBox(height: 20),
                Text(
                  article.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 26 * library.fontScale,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 28),
                if (library.showImages && article.imageUrl.isNotEmpty) ...[
                  ArticleImage(url: article.imageUrl, height: 220),
                  const SizedBox(height: 24),
                ],
                Text(
                  'RSS 摘要',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  article.summary.isEmpty
                      ? '此订阅源未提供摘要，打开原文继续阅读。'
                      : article.summary,
                  style: TextStyle(fontSize: 18 * library.fontScale, height: 2),
                ),
                const SizedBox(height: 28),
                Text(
                  '摘要保存在本机，完整内容请查看原文。远程图片和原文需要联网。',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => OriginalScreen(article: article),
                    ),
                  ),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('打开原文'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final opened = await launchUrl(
                      Uri.parse(article.url),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('用浏览器打开'),
                ),
                TextButton(
                  onPressed: () {
                    final controller = ref.read(libraryProvider.notifier);
                    library.read.contains(article.id)
                        ? controller.markUnread(article.id)
                        : controller.markRead(article.id);
                  },
                  child: Text(
                    library.read.contains(article.id) ? '标记为未读' : '标记为已读',
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: index > 0 ? () => move(index - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('上一篇'),
                    ),
                    Text('${index + 1} / ${queue.length}'),
                    OutlinedButton.icon(
                      onPressed: index < queue.length - 1
                          ? () => move(index + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('下一篇'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OriginalScreen extends StatefulWidget {
  const OriginalScreen({super.key, required this.article});
  final Article article;
  @override
  State<OriginalScreen> createState() => _OriginalScreenState();
}

class _OriginalScreenState extends State<OriginalScreen> {
  late final WebViewController controller;
  int progress = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => error = null);
          },
          onWebResourceError: (value) {
            if (mounted && value.isForMainFrame == true) {
              setState(() => error = '原文加载失败，请检查网络或用浏览器打开');
            }
          },
          onNavigationRequest: (request) => isWebUrl(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadRequest(Uri.parse(widget.article.url));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.article.sourceTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: '重新加载',
          onPressed: controller.reload,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '浏览器打开',
          onPressed: () => launchUrl(
            Uri.parse(widget.article.url),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
    body: Column(
      children: [
        if (progress < 100) LinearProgressIndicator(value: progress / 100),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    ),
  );
}

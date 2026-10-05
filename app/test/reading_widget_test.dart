import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garss_app/main.dart';
import 'package:garss_app/data/models.dart';
import 'package:garss_app/data/repository.dart';
import 'package:garss_app/state/library.dart';

void main() {
  final article = Article(
    id: 'a',
    sourceId: 's',
    title: '可以收藏和离线阅读的文章',
    url: 'https://example.com/post',
    publishedAt: DateTime.utc(2026, 10, 1),
    sourceTitle: '示例来源',
    summary: 'RSS 提供的文章摘要。',
  );
  final catalog = Catalog(
    generatedAt: article.publishedAt,
    feeds: [
      const Feed(id: 's', title: '示例来源', url: 'https://example.com/feed'),
    ],
    articles: [article],
  );
  Future<void> setup(
    WidgetTester tester, {
    double scale = 1,
    Catalog? snapshot,
    List<String> hidden = const [],
  }) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'catalog-v1': jsonEncode((snapshot ?? catalog).toJson()),
      'hidden-v1': hidden,
      'show-images': false,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(
            CatalogRepository(
              MockClient((request) async => http.Response('offline', 503)),
            ),
          ),
        ],
        child: MediaQuery.fromView(
          view: tester.view,
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const GarssApp(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('bookmarks and article summaries work without connectivity', (
    tester,
  ) async {
    await setup(tester);
    await tester.scrollUntilVisible(
      find.text(article.title),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip('加入稍后读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后读').last);
    await tester.pumpAndSettle();
    expect(find.text(article.title), findsOneWidget);
    await tester.tap(find.text(article.title));
    await tester.pumpAndSettle();
    expect(find.text(article.summary), findsOneWidget);
    expect(find.text('打开原文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('removing a saved article offers undo in the focused reader', (
    tester,
  ) async {
    await setup(tester);
    await tester.scrollUntilVisible(
      find.text(article.title),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip('加入稍后读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(article.title));
    await tester.pumpAndSettle();
    expect(find.text('本次筛选 · 第 1 / 1 篇'), findsOneWidget);
    await tester.tap(find.byTooltip('移出稍后读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移出稍后读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('source search and health combine with local follow scope', (
    tester,
  ) async {
    await setup(
      tester,
      snapshot: Catalog(
        generatedAt: catalog.generatedAt,
        articles: [article],
        feeds: const [
          Feed(
            id: 's',
            title: '关注的异常来源',
            url: 'https://example.com/rss',
            status: 'error',
          ),
          Feed(
            id: 'hidden',
            title: '未关注的异常来源',
            url: 'https://example.net/rss',
            status: 'error',
          ),
        ],
      ),
      hidden: ['hidden'],
    );
    await tester.tap(find.text('订阅源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看本机关注'));
    await tester.tap(find.text('采集异常'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('关注的异常来源'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('未关注的异常来源'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reading sources can be searched without changing the query filter',
    (tester) async {
      await setup(tester);
      await tester.tap(find.text('选择阅读来源'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '搜索来源或分类'), '不匹配');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的来源，试试其他关键词。'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '搜索来源或分类'), '示例');
      await tester.pumpAndSettle();
      await tester.tap(find.text('示例来源').last);
      await tester.pumpAndSettle();
      expect(find.text(article.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reading controls remain usable at accessibility text scale', (
    tester,
  ) async {
    await setup(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('信息流').first)).scale(10),
      greaterThan(10),
    );
    await tester.scrollUntilVisible(
      find.text(article.title),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('reading and bookmarks keep independent filters', (tester) async {
    await setup(tester);
    await tester.enterText(find.byType(TextField), '没有这个关键词');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的文章'), findsOneWidget);
    await tester.tap(find.text('稍后读').last);
    await tester.pumpAndSettle();
    expect(find.text('这里留给想再读的文章'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('信息流').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '没有这个关键词',
    );
    await tester.tap(find.text('重置筛选').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('current results can be marked read and undone', (tester) async {
    await setup(tester);
    await tester.tap(find.text('当前结果 1 篇全部已读'));
    await tester.pumpAndSettle();
    expect(find.text('已将 1 篇文章标为已读'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('当前结果 1 篇全部已读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'source and settings pages support enlarged text and wide layouts',
    (tester) async {
      await setup(tester, scale: 2);
      for (final size in [
        const Size(360, 720),
        const Size(1024, 768),
        const Size(720, 360),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.tap(find.text('订阅源').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('设置').last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('当前字号 100%'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('当前字号 100%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'reading filters can be applied and reset at enlarged text scale',
    (tester) async {
      await setup(tester, scale: 2);
      await tester.tap(find.text('分类与时间'));
      await tester.pumpAndSettle();
      expect(find.text('筛选文章'), findsOneWidget);
      await tester.tap(find.text('今天'));
      await tester.scrollUntilVisible(
        find.text('应用筛选'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.tap(find.text('应用筛选'));
      await tester.pumpAndSettle();
      expect(find.text('筛选文章'), findsNothing);
      expect(find.text('今天'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('重置筛选').first);
      await tester.pumpAndSettle();
      expect(find.text('分类与时间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

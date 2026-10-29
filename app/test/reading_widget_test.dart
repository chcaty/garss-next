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
import 'package:garss_app/ui/results_page.dart';

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

  Future<void> showResult(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(
      find.descendant(of: find.byType(ResultTile), matching: find.text(title)),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  testWidgets('result page shows unified update and bookmark navigation', (
    tester,
  ) async {
    await setup(tester);
    expect(find.text('全部更新'), findsWidgets);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('拾阅'), findsOneWidget);
    expect(find.text('订阅源'), findsNothing);
    await showResult(tester, article.title);
    expect(find.text(article.title), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('bookmarks and undo work on result cards without connectivity', (
    tester,
  ) async {
    await setup(tester);
    await showResult(tester, article.title);
    await tester.tap(find.byTooltip('加入收藏'));
    await tester.pumpAndSettle();
    expect(find.text('已加入收藏'), findsOneWidget);
    await tester.tap(find.text('我的收藏').last);
    await tester.pumpAndSettle();
    await showResult(tester, article.title);
    await tester.tap(find.byTooltip('移出收藏'));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await showResult(tester, article.title);
    expect(find.byTooltip('移出收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('updates and bookmarks retain independent search filters', (
    tester,
  ) async {
    await setup(tester);
    await tester.enterText(find.byType(TextField), '没有这个关键词');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的内容'), findsOneWidget);
    await tester.tap(find.text('我的收藏').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('全部更新').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '没有这个关键词',
    );
    await tester.tap(find.text('清除筛选').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
  testWidgets('type and new filters use the same result groups and counts', (
    tester,
  ) async {
    final video = Article(
      id: 'video',
      sourceId: 'video-source',
      title: '视频结果',
      url: 'https://example.com/video',
      publishedAt: article.publishedAt,
      contentType: 'video',
      metadata: const {'views': 12345, 'duration': '1:30'},
    );
    await setup(
      tester,
      snapshot: Catalog(
        generatedAt: catalog.generatedAt,
        articles: [article, video],
        feeds: [
          catalog.feeds.first,
          const Feed(
            id: 'video-source',
            title: '视频来源',
            url: 'https://example.com/json',
            adapter: 'bilibili',
            baselineKnown: true,
            newIds: ['video'],
          ),
        ],
      ),
    );
    await tester.tap(find.text('来源、分类与类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视频').first);
    await tester.pumpAndSettle();
    await showResult(tester, '视频结果');
    expect(find.text(article.title), findsNothing);
    expect(find.text('视频结果'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown source baseline does not claim zero new content', (
    tester,
  ) async {
    await setup(tester);
    expect(find.textContaining('较上次采集新增 —'), findsOneWidget);
    await tester.tap(find.text('只看新增'));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact mode keeps metadata and hides excerpts', (tester) async {
    await setup(tester);
    await tester.tap(find.text('紧凑视图'));
    await tester.pumpAndSettle();
    await showResult(tester, article.title);
    expect(find.text(article.summary), findsNothing);
    expect(find.text(article.title), findsWidgets);
  });
  testWidgets('source management and reading settings live in the more menu', (
    tester,
  ) async {
    await setup(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('来源管理').last);
    await tester.pumpAndSettle();
    expect(find.text('本机关注'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读设置').last);
    await tester.pumpAndSettle();
    expect(find.text('阅读与外观'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'result cards and filters support large text, wide and landscape layouts',
    (tester) async {
      await setup(tester, scale: 2);
      for (final size in [
        const Size(360, 720),
        const Size(1024, 768),
        const Size(720, 360),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await showResult(tester, article.title);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

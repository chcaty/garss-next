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
  Future<void> setup(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'catalog-v1': jsonEncode(catalog.toJson()),
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
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const GarssApp(),
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
    await tester.tap(find.byTooltip('收藏文章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(find.text(article.title), findsOneWidget);
    await tester.tap(find.text(article.title));
    await tester.pumpAndSettle();
    expect(find.text(article.summary), findsOneWidget);
    expect(find.text('打开原文'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reading controls remain usable at accessibility text scale', (
    tester,
  ) async {
    await setup(tester, scale: 2);
    expect(tester.takeException(), isNull);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('今日阅读'))).scale(10),
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
    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(find.text('这里留给想再读的文章'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('阅读').last);
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
    await tester.tap(find.text('当前结果全部已读'));
    await tester.pumpAndSettle();
    expect(find.text('已将 1 篇文章标为已读'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('当前结果全部已读'), findsOneWidget);
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
        await tester.tap(find.text('来源').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('设置').last);
        await tester.pumpAndSettle();
        expect(find.text('当前字号 100%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

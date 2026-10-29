import json
import tempfile
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path

from garss.adapters import ADAPTERS, parse_adapter
from garss.models import Article, FeedResult, FeedSource
from garss.history import merge_recent_history
from garss.snapshot import create_snapshot, expand_history


class AdapterTests(unittest.TestCase):
    now = datetime(2026, 10, 29, tzinfo=timezone.utc)

    def source(self, adapter):
        return FeedSource(adapter, adapter, '', ADAPTERS[adapter]['url'], adapter=adapter)

    def test_reused_v2ex_parser_preserves_type_date_metrics_and_safe_links(self):
        payload = json.dumps([{'id':1,'title':'Topic','url':'https://v2ex.com/t/1', 'created':1,
                               'replies':42,'member':{'username':'Alice'},'node':{'title':'Tech'}},
                              {'id':2,'title':'Unsafe','url':'javascript:alert(1)'}]).encode()
        articles = parse_adapter(self.source('v2ex'), payload, self.now)
        self.assertEqual(len(articles), 1)
        self.assertEqual(articles[0].content_type, 'topic')
        self.assertEqual(articles[0].metadata['replies'], 42)
        self.assertFalse(articles[0].date_inferred)

    def test_bilibili_error_response_is_not_an_empty_success(self):
        with self.assertRaises(ValueError):
            parse_adapter(self.source('bilibili'), b'{"code":-412}', self.now)

    def test_reference_rss_uses_actual_endpoints_rather_than_similarly_named_columns(self):
        from garss.catalog import load_sources
        sources = load_sources(Path(__file__).resolve().parents[1] / 'sources.json')['sources']
        urls = {source['feed_url'] for source in sources if source.get('adapter', 'rss') == 'rss'}
        for url in ('https://www.ithome.com/rss/', 'https://www.ifanr.com/feed',
                    'https://www.cnbeta.com.tw/backend.php', 'https://www.solidot.org/index.rss',
                    'https://www.qbitai.com/feed', 'https://www.leiphone.com/feed',
                    'https://www.oschina.net/news/rss', 'https://www.ruanyifeng.com/blog/atom.xml',
                    'https://techcrunch.com/feed/', 'https://www.theverge.com/rss/index.xml',
                    'https://feeds.arstechnica.com/arstechnica/index',
                    'https://feeds.bbci.co.uk/zhongwen/simp/rss.xml', 'https://cn.nytimes.com/rss/'):
            self.assertIn(url, urls)
        self.assertEqual({source.get('adapter', 'rss') for source in sources}, set(ADAPTERS))

    def test_json_adapter_shapes_keep_typed_metrics_and_safe_images(self):
        cases = {
            'weibo_hot': ({'data': {'realtime': [{'word': 'Topic', 'num': 12500}]}}, 'topic', 'heat', 12500),
            'toutiao': ({'data': [{'Title': 'Topic', 'ClusterId': 1, 'HotValue': '12500'}]}, 'topic', 'heat', 12500),
            'bilibili': ({'code': 0, 'data': {'list': [{'bvid': 'BV1', 'title': 'Video', 'owner': {'name': 'Creator'}, 'duration': 90, 'pubdate': 1, 'pic': 'javascript:bad', 'stat': {'view': 12500}}]}}, 'video', 'views', 12500),
            'sspai': ({'data': [{'id': 1, 'title': 'Article', 'released_time': 1, 'comment_count': 12}]}, 'article', 'replies', 12),
            'bili_hotword': ({'list': [{'keyword': 'Topic'}]}, 'topic', 'rank', 1),
            'zhihu_daily': ({'stories': [{'id': 1, 'title': 'Article'}]}, 'article', 'rank', 1),
            'douban_hot': ({'subjects': [{'id': 1, 'title': 'Film', 'url': 'https://example.com/1', 'rate': '8.6'}]}, 'item', 'rating', 8.6),
            'douban_new': ({'data': [{'id': 1, 'title': 'Film', 'url': 'https://example.com/1', 'rate': '8.6'}]}, 'item', 'rating', 8.6),
            'juejin': ({'data': [{'content': {'content_id': '1', 'title': 'Article'}, 'content_counter': {'view': 123456, 'like': 12345}}]}, 'article', 'likes', 12345),
            'lobsters': ([{'short_id': '1', 'title': 'Article', 'score': -2, 'created_at': '2026-10-28T00:00:00Z'}], 'article', 'score', -2),
            'devto': ([{'id': 1, 'title': 'Article', 'url': 'https://example.com/1', 'positive_reactions_count': 12345, 'published_at': '2026-10-28T00:00:00Z'}], 'article', 'likes', 12345),
            'stackoverflow': ({'items': [{'question_id': 1, 'title': 'Question', 'link': 'https://example.com/1', 'creation_date': 1, 'score': -1, 'answer_count': 12}]}, 'topic', 'answers', 12),
            'baidu_pc': ({'data': {'cards': [{'content': [{'query': 'Topic', 'hotScore': '12345'}]}]}}, 'topic', 'heat', 12345),
        }
        for adapter, (payload, kind, metric, expected) in cases.items():
            with self.subTest(adapter=adapter):
                article = parse_adapter(self.source(adapter), json.dumps(payload).encode(), self.now)[0]
                self.assertEqual(article.content_type, kind)
                self.assertEqual(article.metadata[metric], expected)
                self.assertTrue(article.url.startswith('https://'))
                if adapter == 'bilibili':
                    self.assertEqual(article.metadata['author'], 'Creator')
                    self.assertEqual(article.metadata['duration'], '1:30')
                    self.assertEqual(article.image_url, '')

    def test_hn_secondary_requests_preserve_timestamp_and_fail_as_a_complete_source(self):
        calls = []
        def read(url):
            calls.append(url)
            return {'id': 1, 'title': 'Story', 'by': 'Author', 'time': 1, 'score': 12, 'descendants': 3}
        article = parse_adapter(self.source('hn'), b'[1]', self.now, fetch_json=read)[0]
        self.assertEqual(calls, ['https://hacker-news.firebaseio.com/v0/item/1.json'])
        self.assertEqual(article.metadata['score'], 12)
        self.assertEqual(article.metadata['replies'], 3)
        self.assertEqual(article.published_at.year, 1970)
        self.assertFalse(article.date_inferred)
        def partial(url):
            if url.endswith('/2.json'):
                raise ValueError('offline')
            return read(url)
        with self.assertRaisesRegex(ValueError, 'preserving previous'):
            parse_adapter(self.source('hn'), b'[1,2]', self.now, fetch_json=partial)
        with self.assertRaises(ValueError):
            parse_adapter(self.source('hn'), b'["../secrets"]', self.now, fetch_json=read)

    def test_optional_html_sources_parse_without_fetching_or_executing_page_content(self):
        movie = b'<div class="item"><a href="/v/abc" class="box"></a><div class="video-title"><strong>CODE</strong>Example</div>8.5 \xe5\x88\x86, \xe7\x94\xb1 12 \xe4\xba\xba\xe8\xa9\x95\xe5\x83\xb9</div>'
        article = parse_adapter(self.source('javdb'), movie, self.now)[0]
        self.assertEqual(article.content_type, 'item')
        self.assertEqual(article.metadata['rating'], 8.5)
        news = b'<article><meta itemprop="url mainEntityOfPage" content="/post/1"><h2>Example</h2><meta itemprop="datePublished" content="2026-10-28T12:00:00"></article>'
        article = parse_adapter(self.source('gossip'), news, self.now)[0]
        self.assertEqual(article.published_at.utcoffset(), timedelta(hours=8))
        self.assertFalse(article.date_inferred)

    def test_future_and_invalid_dates_and_unrecognized_html(self):
        payload = [{'id': 1, 'title': 'Future', 'url': 'https://example.com/1', 'published_at': '2100-01-01T00:00:00Z'},
                   {'id': 2, 'title': 'Invalid date', 'url': 'https://example.com/2', 'published_at': 'bad'}]
        articles = parse_adapter(self.source('devto'), json.dumps(payload).encode(), self.now)
        self.assertEqual(len(articles), 1)
        self.assertTrue(articles[0].date_inferred)
        self.assertEqual(articles[0].published_at, self.now)
        with self.assertRaisesRegex(ValueError, 'no recognized'):
            parse_adapter(self.source('github-trending'), b'<html>Access denied</html>', self.now)

    def test_reused_trending_parser_and_inferred_first_seen_survive_history(self):
        source = self.source('github-trending')
        payload = b'<article class="Box-row"><h2><a href="/owner/repo">owner/repo</a></h2><p class="col-9">Description</p><span itemprop="programmingLanguage">Python</span><a href="/owner/repo/stargazers">1,234</a><span>20 stars today</span></article>'
        article = parse_adapter(source, payload, self.now)[0]
        self.assertEqual(article.metadata['stars'], 1234)
        self.assertEqual(article.metadata['stars_today'], 20)
        old = Article(source.id, 'Old title', article.url, self.now-timedelta(days=60), date_inferred=True,
                      content_type='repository', metadata={'stars':1})
        expired = Article(source.id, 'Off board', 'https://github.com/x/y', self.now)
        results = merge_recent_history([FeedResult(source, [article])], [old, expired], self.now.date(), 30)
        self.assertEqual(len(results[0].articles), 1)
        self.assertEqual(results[0].articles[0].published_at, old.published_at)
        self.assertEqual(results[0].articles[0].metadata['stars'], 1234)
        restored = expand_history([results[0].articles[0].as_dict()])[0]
        self.assertEqual(restored.metadata['stars'], 1234)

    def test_snapshot_new_ids_initialize_compare_and_ignore_failed_collections(self):
        source = self.source('v2ex')
        config = {'sources':[{'id':source.id,'title':'V2EX','feed_url':source.feed_url,'adapter':'v2ex','enabled':True}]}
        old = Article(source.id, 'Old', 'https://example.com/old', self.now, content_type='topic', metadata={'rank':2})
        new = Article(source.id, 'New', 'https://example.com/new', self.now, content_type='topic', metadata={'rank':1})
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            def snapshot(name, results, prior, feeds):
                folder=root/name
                create_snapshot(folder, results, config, self.now, previous_articles=prior, previous_feeds=feeds)
                return json.loads((folder/'api/v1/feeds.json').read_text(encoding='utf-8'))['feeds'][0]
            first = snapshot('first',[FeedResult(source,[old])],[],[])
            self.assertIsNone(first['new_count'])
            self.assertFalse(first['baseline_known'])
            second = snapshot('second',[FeedResult(source,[old,new])],[old],[first])
            self.assertEqual(second['new_count'], 1)
            failed = snapshot('failed',[FeedResult(source,[old,new],error='offline')],[old,new],[second])
            self.assertEqual(failed['new_ids'], [])
            self.assertIsNone(failed['new_count'])
            self.assertEqual(failed['collected_at'], second['collected_at'])
            document=json.loads((root/'second/api/v1/articles.json').read_text(encoding='utf-8'))
            fresh=next(item for item in document['articles'] if item['url']==new.url)
            self.assertEqual(second['new_ids'], [fresh['id']])
            self.assertEqual(fresh['observations']['v2ex']['rank'], 1)

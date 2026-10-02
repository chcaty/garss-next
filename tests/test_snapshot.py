import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from garss.models import Article, FeedResult, FeedSource
from garss.snapshot import consolidate, create_snapshot, expand_history, validate_snapshot


class SnapshotTests(unittest.TestCase):
    def test_cross_source_duplicates_keep_all_source_relations_and_stable_identity(self):
        a = FeedSource('a', 'A', '', 'https://example.com/feed')
        b = FeedSource('b', 'B', '', 'https://example.com/rss')
        now = datetime(2026, 10, 1, tzinfo=timezone.utc)
        first = Article('a', 'Article', 'https://example.com/post#reply0', now)
        second = Article('b', 'Article', 'https://example.com/post?utm_source=rss#reply3', now, 'Summary')
        articles = consolidate([FeedResult(a, [first]), FeedResult(b, [second])])
        self.assertEqual(len(articles), 1)
        self.assertEqual(articles[0]['source_ids'], ['a', 'b'])
        self.assertEqual(articles[0]['summary'], 'Summary')
        reversed_articles = consolidate([FeedResult(b, [second]), FeedResult(a, [first])])
        self.assertEqual(articles[0]['id'], reversed_articles[0]['id'])
        self.assertEqual({item.source_id for item in expand_history(articles)}, {'a', 'b'})

    def test_snapshot_integrity_and_disabled_sources(self):
        source = FeedSource('a', 'A', '', 'https://example.com/feed')
        config = {'schema_version':'1.0', 'sources':[
            {'id':'a', 'title':'A', 'description':'', 'feed_url':source.feed_url, 'category':'Tech', 'enabled':True},
            {'id':'b', 'title':'B', 'description':'', 'feed_url':'https://example.com/rss', 'category':'Tech', 'enabled':False}]}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            identity = create_snapshot(root, [FeedResult(source)], config, datetime.now(timezone.utc))
            self.assertEqual(validate_snapshot(root)['snapshot_id'], identity)
            (root / 'api/v1/snapshots' / identity / 'articles.json').write_text('{}')
            with self.assertRaises(ValueError):
                validate_snapshot(root)

    def test_empty_configuration_is_valid_and_disabling_source_stops_collection(self):
        from garss.catalog import feed_sources
        self.assertEqual(feed_sources({'sources':[]}), [])
        self.assertEqual(feed_sources({'sources':[{'id':'a','title':'A','description':'','feed_url':'https://example.com/rss','enabled':False}]}), [])

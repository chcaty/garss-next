import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from garss.models import Article, FeedResult, FeedSource
from garss.snapshot import create_snapshot, validate_snapshot
from garss.app_snapshot import validate_app_snapshot


class AppSnapshotTests(unittest.TestCase):
    now = datetime(2026, 11, 4, 1, tzinfo=timezone.utc)
    source = FeedSource('a', 'A', '', 'https://example.com/feed')
    config = {'sources': [{'id': 'a', 'title': 'A', 'feed_url': source.feed_url}]}

    def read(self, root):
        meta = validate_app_snapshot(root)
        folder = root / 'api/v1/app/snapshots' / meta['snapshot_id']
        return meta, json.loads((folder / 'articles.json').read_text()), json.loads((folder / 'feeds.json').read_text())

    def test_strict_shanghai_boundary_and_no_quiet_source_minimum(self):
        # Shanghai Oct 31 00:00 is the oldest included instant on Nov 4.
        dates = ['2026-10-30T15:59:59+00:00', '2026-10-30T16:00:00+00:00',
                 '2026-11-04T15:59:59+00:00', '2026-11-04T16:00:00+00:00',
                 '2026-10-01T00:00:00+00:00']
        articles = [Article('a', str(i), f'https://example.com/{i}', datetime.fromisoformat(date))
                    for i, date in enumerate(dates)]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            create_snapshot(root, [FeedResult(self.source, articles)], self.config, self.now)
            meta, mobile, feeds = self.read(root)
            self.assertEqual({a['title'] for a in mobile['articles']}, {'1', '2'})
            self.assertEqual(feeds['feeds'][0]['article_count'], 2)
            self.assertEqual(meta['minimum_articles_per_source'], 0)
            self.assertEqual(len(json.loads((root / 'api/v1/articles.json').read_text())['articles']), 5)
            self.assertEqual(validate_snapshot(root)['retention_days'], 30)

    def test_stable_identity_reuses_bytes_and_next_day_rotates(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            one, two, three = [root / name for name in ('one', 'two', 'three')]
            create_snapshot(one, [], {'sources': []}, self.now)
            create_snapshot(two, [], {'sources': []}, self.now + timedelta(hours=1), previous_root=one)
            a, _, _ = self.read(one)
            b, _, _ = self.read(two)
            self.assertEqual(a, b)
            folder = 'api/v1/app/snapshots/' + a['snapshot_id']
            for name in ('manifest.json', 'articles.json', 'feeds.json'):
                self.assertEqual((one / folder / name).read_bytes(), (two / folder / name).read_bytes())
            create_snapshot(three, [], {'sources': []}, self.now + timedelta(days=1), previous_root=two)
            c, _, _ = self.read(three)
            self.assertNotEqual(a['snapshot_id'], c['snapshot_id'])
            self.assertEqual({p.name for p in (three / 'api/v1/app/snapshots').iterdir()}, {a['snapshot_id'], c['snapshot_id']})

    def test_tampered_app_bytes_block_full_tree_validation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            create_snapshot(root, [], {'sources': []}, self.now)
            meta, _, _ = self.read(root)
            path = root / 'api/v1/app/snapshots' / meta['snapshot_id'] / 'articles.json'
            path.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'Mobile snapshot integrity'):
                validate_snapshot(root)

    def test_counts_new_ids_and_aliases_match_projected_items(self):
        old = Article('a', 'Old', 'https://example.com/old', self.now - timedelta(days=8))
        fresh = Article('a', 'New', 'https://example.com/new', self.now)
        config = {**self.config, 'source_aliases': {'legacy': 'a'}}
        prior_feeds = [{'id': 'a', 'feed_url': self.source.feed_url, 'status': 'ok', 'initialized': True}]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            create_snapshot(root, [FeedResult(self.source, [old, fresh])], config, self.now,
                            previous_articles=[], previous_feeds=prior_feeds)
            _, articles, feeds = self.read(root)
            feed = feeds['feeds'][0]
            self.assertEqual(feed['article_count'], 1)
            self.assertEqual(feed['new_count'], 1)
            self.assertEqual(feed['new_ids'], [articles['articles'][0]['id']])
            self.assertEqual(feeds['source_aliases'], {'legacy': 'a'})
            self.assertGreater(len(articles['articles'][0]['legacy_ids']), 1)

    def test_collection_time_alone_does_not_rotate_mobile_snapshot(self):
        article = Article('a', 'Article', 'https://example.com/item', self.now)
        prior_feeds = [{'id': 'a', 'feed_url': self.source.feed_url, 'status': 'ok', 'initialized': True}]
        with tempfile.TemporaryDirectory() as temp:
            one, two = Path(temp) / 'one', Path(temp) / 'two'
            for root, now, previous in ((one, self.now, None), (two, self.now + timedelta(hours=2), one)):
                create_snapshot(root, [FeedResult(self.source, [article])], self.config, now,
                                previous_articles=[article], previous_feeds=prior_feeds, previous_root=previous)
            self.assertEqual(self.read(one)[0], self.read(two)[0])

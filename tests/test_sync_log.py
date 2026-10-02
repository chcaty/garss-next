import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from garss.catalog import load_sources
from garss.models import FeedResult, FeedSource
from garss.sync_log import publication_log


class SyncLogTests(unittest.TestCase):
    def test_records_attempts_separately_from_retained_articles_and_bounds_history(self):
        start = datetime(2026, 10, 3, tzinfo=timezone.utc)
        source = FeedSource('a', 'A', '', 'https://example.com/rss')
        results = [FeedResult(source), FeedResult(source, error='timeout')]
        document = publication_log({'runs': [{'generated_at': str(index)} for index in range(50)]},
                                   results, {'a': {'status': 'active'}, 'b': {'status': 'archived'}},
                                   start, start + timedelta(seconds=60), 100, 'revision', '123')
        self.assertEqual(len(document['runs']), 30)
        latest = document['runs'][0]
        self.assertEqual((latest['checked'], latest['succeeded'], latest['failed']), (2, 1, 1))
        self.assertEqual((latest['article_count'], latest['duration_seconds'], latest['archived']), (100, 60, 1))
        self.assertEqual(document['runs'][1]['generated_at'], '0')

    def test_duplicate_feed_fragments_rejected_but_distinct_columns_allowed(self):
        source = {'id': 'a', 'title': 'A', 'description': '', 'category': 'News', 'feed_url': 'https://example.com/rss'}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'sources.json'
            config = {'schema_version': '1.0', 'sources': [source, {**source, 'id': 'b', 'feed_url': 'https://EXAMPLE.com/rss#fragment'}]}
            path.write_text(json.dumps(config), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Duplicate RSS URL'):
                load_sources(path)
            config['sources'][1]['feed_url'] = 'https://example.com/news/rss'
            path.write_text(json.dumps(config), encoding='utf-8')
            self.assertEqual(len(load_sources(path)['sources']), 2)

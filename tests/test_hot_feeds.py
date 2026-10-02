import unittest
from datetime import datetime, timezone, timedelta
from garss.fetch import _parse_articles
from garss.models import FeedSource, Article, FeedResult
from garss.history import merge_recent_history
from garss.snapshot import expand_history
from garss.timezones import app_date

class HotFeedTests(unittest.TestCase):
    def test_undated_entries_require_explicit_opt_in(self):
        payload=b'<rss version="2.0"><channel><title>Hot</title><link>https://test.example</link><description>Hot</description><item><title>Topic</title><link>https://test.example/topic</link></item></channel></rss>'
        ordinary=FeedSource('a','A','','https://test.example/rss')
        self.assertEqual(_parse_articles(ordinary,payload),[])
        hot=FeedSource('a','A','','https://test.example/rss',True)
        articles=_parse_articles(hot,payload)
        self.assertEqual(len(articles),1)
        self.assertTrue(articles[0].date_inferred)
        self.assertTrue(expand_history([articles[0].as_dict()])[0].date_inferred)
    def test_repeated_hot_collection_preserves_first_seen_and_identity(self):
        now=datetime.now(timezone.utc);source=FeedSource('a','A','','https://test.example/rss',True)
        previous=Article('a','Old','https://test.example/topic',now-timedelta(hours=3),date_inferred=True)
        new=Article('a','Updated','https://test.example/topic',now,date_inferred=True)
        merged=merge_recent_history([FeedResult(source,[new])],[previous],app_date(now),30)[0].articles
        self.assertEqual(len(merged),1)
        self.assertEqual(merged[0].id,previous.id)
        self.assertEqual(merged[0].published_at,previous.published_at)
        self.assertEqual(merged[0].title,'Updated')

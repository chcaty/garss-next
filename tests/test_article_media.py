import unittest
from datetime import date, datetime, timezone
from unittest.mock import Mock
from garss.history import enrich_cached_articles
from garss.models import Article, FeedSource
from garss.text import plain_summary, entry_image


class ArticleMediaTests(unittest.TestCase):
    def test_plain_summary_removes_scripts_decodes_entities_and_bounds_length(self):
        self.assertEqual(plain_summary('<p>Hello &amp; world</p><script>alert(1)</script><style>.x{}</style><p>Next</p>'), 'Hello & world Next')
        self.assertEqual(len(plain_summary('a' * 1000)), 600)

    def test_media_thumbnail_precedes_content_and_relative_images_resolve(self):
        self.assertEqual(entry_image({'media_thumbnail': [{'url': '/cover.jpg'}], 'summary': '<img src="other.jpg">'}, 'https://example.com/post/'), 'https://example.com/cover.jpg')
        self.assertEqual(entry_image({'content': [{'value': '<img src="../image.jpg">'}]}, 'https://example.com/post/'), 'https://example.com/image.jpg')

    def test_unsafe_images_are_skipped_and_missing_image_is_empty(self):
        self.assertEqual(entry_image({'summary': '<img src="javascript:alert(1)"><img src="https://user:pass@example.com/i.jpg"><img src="https://example.com/good.jpg">'}, 'https://example.com/post'), 'https://example.com/good.jpg')
        self.assertEqual(entry_image({}, 'https://example.com'), '')

    def test_backfill_enriches_existing_history_without_admitting_old_new_posts(self):
        source = FeedSource('id', 'Title', '', 'https://example.com/feed')
        old = Article('id', 'Original title', 'https://example.com/old', datetime(2026, 10, 1, tzinfo=timezone.utc))
        payload = b'<rss version="2.0"><channel><title>Example</title><item><title>Changed title</title><link>https://example.com/old</link><pubDate>Thu, 01 Oct 2026 08:00:00 GMT</pubDate><description>&lt;p&gt;Summary&lt;/p&gt;&lt;img src="/image.jpg"&gt;</description></item><item><title>Not in history</title><link>https://example.com/missing</link><pubDate>Thu, 01 Oct 2026 08:00:00 GMT</pubDate></item></channel></rss>'
        cache = Mock()
        cache.get.return_value.payload = payload
        enriched = enrich_cached_articles([old], [source], cache, date(2026, 10, 2), 30)
        self.assertEqual(len(enriched), 1)
        self.assertEqual(enriched[0].id, old.id)
        self.assertEqual(enriched[0].title, old.title)
        self.assertEqual(enriched[0].summary, 'Summary')
        self.assertEqual(enriched[0].image_url, 'https://example.com/image.jpg')

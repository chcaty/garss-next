import unittest
import json
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path

from garss.history import load_cached_articles, merge_recent_history
from garss.models import Article, FeedResult, FeedSource
from garss.article_identity import article_key


class HistoryTests(unittest.TestCase):
    def test_repeated_collection_merges_reply_anchors_and_keeps_old_id(self):
        source = FeedSource('X001', 'Example', '', 'https://example.com/feed')
        old = Article(source.id, 'Topic', 'https://example.com/t/42#reply0',
                      datetime(2026, 9, 29, tzinfo=timezone.utc), summary='Cached summary')
        fresh = Article(source.id, 'Topic updated', 'https://example.com/t/42#reply3',
                        datetime(2026, 9, 30, tzinfo=timezone.utc))
        results = merge_recent_history([FeedResult(source, [fresh])], [old],
                                       date(2026, 9, 30), 30)
        merged = results[0].articles
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].id, old.id)
        self.assertEqual(merged[0].title, fresh.title)
        self.assertEqual(merged[0].summary, old.summary)
        repeated = merge_recent_history([FeedResult(source, [fresh])], merged,
                                        date(2026, 9, 30), 30)
        self.assertEqual(repeated[0].articles, merged)

    def test_identity_drops_tracking_but_preserves_content_and_hash_routes(self):
        self.assertEqual(article_key('https://example.com/post?id=42&utm_source=rss#reply1'),
                         article_key('https://example.com/post?id=42'))
        self.assertNotEqual(article_key('https://example.com/post?id=42'),
                            article_key('https://example.com/post?id=43'))
        self.assertNotEqual(article_key('https://example.com/#/post/42'),
                            article_key('https://example.com/#/post/43'))

    def test_today_is_merged_with_recent_cache_and_expired_items_are_removed(self):
        source = FeedSource(
            "X001", "Example", "Example feed", "https://example.com/feed.xml"
        )
        today_article = Article(
            source.id,
            "Today",
            "https://example.com/today",
            datetime(2026, 9, 30, tzinfo=timezone.utc),
        )
        cached_articles = [
            Article(
                source.id,
                "Yesterday",
                "https://example.com/yesterday",
                datetime(2026, 9, 29, tzinfo=timezone.utc),
            ),
            Article(
                source.id,
                "Boundary",
                "https://example.com/boundary",
                datetime(2026, 9, 1, tzinfo=timezone.utc),
            ),
            Article(
                source.id,
                "Outside window",
                "https://example.com/outside",
                datetime(2026, 8, 31, tzinfo=timezone.utc),
            ),
            Article(
                "removed-source",
                "Removed source",
                "https://example.com/removed",
                datetime(2026, 9, 29, tzinfo=timezone.utc),
            ),
            Article(
                source.id,
                "Expired",
                "https://example.com/expired",
                datetime(2026, 8, 1, tzinfo=timezone.utc),
            ),
            Article(
                source.id,
                "Future",
                "https://example.com/future",
                datetime(2026, 10, 1, tzinfo=timezone.utc),
            ),
        ]
        results = [FeedResult(source=source, articles=[today_article])]

        merged = merge_recent_history(
            results,
            cached_articles,
            today=date(2026, 9, 30),
            retention_days=30,
            minimum_articles=0,
        )

        self.assertEqual(
            [article.title for article in merged[0].articles],
            ["Today", "Yesterday", "Boundary"],
        )

    def test_malformed_cache_structure_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "articles.json"
            for payload in ([], None, {"articles": None}, {"articles": {}}):
                path.write_text(json.dumps(payload), encoding="utf-8")
                with self.assertLogs("garss.history", level="WARNING"):
                    self.assertEqual(load_cached_articles(path, {"X001"}), [])


if __name__ == "__main__":
    unittest.main()

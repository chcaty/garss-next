import unittest
from datetime import date, datetime, timezone

from garss.article_retention import retain_articles
from garss.fetch import _parse_articles
from garss.history import merge_recent_history
from garss.models import Article, FeedResult, FeedSource


class ArticleRetentionTests(unittest.TestCase):
    def article(self, name, day, source="X"):
        return Article(source, name, f"https://example.com/{name}", datetime.fromisoformat(day).replace(tzinfo=timezone.utc))

    def test_quiet_feed_keeps_five_latest_valid_posts_in_date_order(self):
        source = FeedSource("X", "Quiet", "", "https://example.com/feed")
        items = [f'<item><title>Post {i}</title><link>https://example.com/{i}</link><pubDate>2024-01-{i:02d}T00:00:00Z</pubDate></item>' for i in range(1, 8)]
        items += [items[-1], '<item><title>Unsafe</title><link>javascript:alert(1)</link><pubDate>2026-09-01T00:00:00Z</pubDate></item>', '<item><title>Future</title><link>https://example.com/future</link><pubDate>2030-01-01T00:00:00Z</pubDate></item>']
        payload = ('<rss version="2.0"><channel><title>Quiet</title>' + ''.join(items) + '</channel></rss>').encode()
        for only_date in (None, date(2026, 10, 2)):
            articles = _parse_articles(source, payload, today=date(2026, 10, 2), only_date=only_date)
            self.assertEqual([a.title for a in articles], [f"Post {i}" for i in range(7, 2, -1)])

    def test_recent_window_is_not_capped_and_latest_posts_fill_only_the_shortfall(self):
        recent = [self.article(f"recent{i}", f"2026-09-{i:02d}") for i in range(3, 11)]
        old = [self.article(f"old{i}", f"2024-01-{i:02d}") for i in range(1, 8)]
        today = date(2026, 10, 2)
        self.assertEqual(len(retain_articles(recent + old, today, 30)), 8)
        retained = retain_articles(recent[:2] + old, today, 30)
        self.assertEqual([a.title for a in retained], ["recent4", "recent3", "old7", "old6", "old5"])

    def test_failed_fetch_keeps_each_source_archive_without_future_or_removed_sources(self):
        sources = [FeedSource(id, id, "", f"https://example.com/{id}") for id in ("X", "Y")]
        cached = [self.article(f"{source}{i}", f"2024-01-{i:02d}", source) for source in ("X", "Y", "removed") for i in range(1, 8)]
        cached.append(self.article("future", "2030-01-01", "X"))
        replacement = self.article("X7", "2024-01-07", "X")
        results = [FeedResult(sources[0], [replacement]), FeedResult(sources[1], error="timeout")]
        merged = merge_recent_history(results, cached, date(2026, 10, 2), 30)
        self.assertEqual([len(r.articles) for r in merged], [5, 5])
        self.assertIs(merged[0].articles[0], replacement)
        self.assertEqual(merged[1].status, "error")
        self.assertEqual({a.source_id for r in merged for a in r.articles}, {"X", "Y"})


if __name__ == "__main__":
    unittest.main()

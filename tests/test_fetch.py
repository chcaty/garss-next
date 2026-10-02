import unittest
import tempfile
from datetime import date
from pathlib import Path
from unittest.mock import Mock, patch
import requests

from garss.fetch import MAX_FEED_BYTES, _download_feed, _parse_articles, fetch_feed, _retry_after_seconds
from garss.feed_cache import FeedCache, CachedFeed
from garss.models import FeedSource


class FakeResponse:
    def __init__(self, chunks, content_length=None, status=200):
        self.chunks = chunks
        self.headers = {}
        self.closed = False
        self.status_code = status
        if content_length is not None:
            self.headers["Content-Length"] = str(content_length)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError("HTTP failure", response=self)
        return None

    def iter_content(self, chunk_size):
        return iter(self.chunks)

    def close(self):
        self.closed = True


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.source = FeedSource(
            "X001", "Example", "Example feed", "https://example.com/feed.xml"
        )

    def test_retry_after_supports_seconds_dates_and_invalid_values(self):
        self.assertEqual(_retry_after_seconds("7", 0), 7)
        self.assertEqual(_retry_after_seconds("Thu, 01 Jan 1970 00:00:10 GMT", 3), 7)
        self.assertEqual(_retry_after_seconds("Thu, 01 Jan 1970 00:00:10 GMT", 30), 0)
        for value in (None, "bad", "-3", "1.5"):
            self.assertEqual(_retry_after_seconds(value, 0), 0)

    def test_retry_after_is_honored_without_exceeding_retry_budget(self):
        for wait, expected_calls in [(7, 2), (120, 1), (10**1000, 1)]:
            with self.subTest(wait=wait):
                response = FakeResponse([], status=429)
                response.headers["Retry-After"] = str(wait)
                get = Mock(return_value=response)
                sleep = Mock()
                fetch_feed(self.source, request_get=get, sleep=sleep, attempts=2,
                           clock=lambda: 0, budget_seconds=45)
                self.assertEqual(get.call_count, expected_calls)
                if expected_calls == 2:
                    sleep.assert_called_once_with(7)
                else:
                    sleep.assert_not_called()

    def test_no_store_and_vary_star_remove_old_cache_even_if_body_is_invalid(self):
        for header, value in [("Cache-Control", "public, NO-STORE"), ("Vary", "*"), ("Vary", "Accept, *")]:
            with self.subTest(header=header), tempfile.TemporaryDirectory() as directory:
                cache = FeedCache(Path(directory))
                cache.put(self.source.feed_url, CachedFeed(b"previous", '"old"'))
                response = FakeResponse([b"not XML"])
                response.headers[header] = value
                fetch_feed(self.source, cache=cache, request_get=lambda *a, **k: response)
                self.assertIsNone(cache.get(self.source.feed_url))

    def test_304_refreshes_without_rewriting_body_but_persists_changed_validators(self):
        payload = b'<rss version="2.0"><channel><title>Feed</title></channel></rss>'
        with tempfile.TemporaryDirectory() as directory:
            cache = FeedCache(Path(directory))
            cache.put(self.source.feed_url, CachedFeed(payload, '"old"'))
            unchanged = cache._path(self.source.feed_url).read_bytes()
            response = FakeResponse([], status=304)
            with patch.object(cache, "put", wraps=cache.put) as put, patch.object(cache, "touch", wraps=cache.touch) as touch:
                fetch_feed(self.source, cache=cache, request_get=lambda *a, **k: response)
                put.assert_not_called()
                touch.assert_called_once()
            self.assertEqual(cache._path(self.source.feed_url).read_bytes(), unchanged)
            response.headers["ETag"] = '"new"'
            fetch_feed(self.source, cache=cache, request_get=lambda *a, **k: response)
            self.assertEqual(cache.get(self.source.feed_url).etag, '"new"')

    def test_invalid_compression_falls_back_to_a_fresh_fetch(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = FeedCache(Path(directory))
            cache._path(self.source.feed_url).write_bytes(b"\x1f\x8b\x08\x00\x00\x00\x00\x00\x00\xff\x06")
            self.assertIsNone(cache.get(self.source.feed_url))
            response = FakeResponse([b'<rss version="2.0"><channel><title>Feed</title></channel></rss>'])
            get = Mock(return_value=response)
            result = fetch_feed(self.source, cache=cache, request_get=get)
            self.assertEqual(result.status, "ok")
            self.assertNotIn("If-None-Match", get.call_args.kwargs["headers"])

    def test_304_reparses_body_and_keeps_latest_posts_on_the_next_day(self):
        payload = b'<rss version="2.0"><channel><title>Feed</title><item><title>Old</title><link>https://example.com/item</link><pubDate>Wed, 30 Sep 2026 08:00:00 GMT</pubDate></item></channel></rss>'
        with tempfile.TemporaryDirectory() as directory:
            cache = FeedCache(Path(directory))
            first = FakeResponse([payload])
            first.headers["ETag"] = '"revision1"'
            first.headers["Last-Modified"] = "Wed, 30 Sep 2026 08:00:00 GMT"
            get = Mock(return_value=first)
            result = fetch_feed(self.source, today=date(2026, 9, 30), only_date=date(2026, 9, 30), cache=cache, request_get=get)
            self.assertEqual(len(result.articles), 1)
            second = FakeResponse([], status=304)
            get.return_value = second
            result = fetch_feed(self.source, today=date(2026, 10, 1), only_date=date(2026, 10, 1), cache=cache, request_get=get)
            self.assertEqual(result.status, "ok")
            self.assertEqual([article.title for article in result.articles], ["Old"])
            self.assertEqual(get.call_args.kwargs["headers"]["If-None-Match"], '"revision1"')
            self.assertIn("If-Modified-Since", get.call_args.kwargs["headers"])
            self.assertEqual(cache.get(self.source.feed_url).etag, '"revision1"')
            self.assertTrue(first.closed and second.closed)

    def test_permanent_http_errors_are_not_retried(self):
        response = FakeResponse([], status=404)
        get = Mock(return_value=response)
        sleep = Mock()
        result = fetch_feed(self.source, request_get=get, sleep=sleep)
        self.assertEqual(result.status, "error")
        self.assertEqual(get.call_count, 1)
        sleep.assert_not_called()
        self.assertTrue(response.closed)

    def test_malformed_response_does_not_replace_a_valid_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = FeedCache(Path(directory))
            cache.put(self.source.feed_url, CachedFeed(b"previous", '"old"'))
            response = FakeResponse([b"not XML"])
            result = fetch_feed(self.source, cache=cache, request_get=lambda *a, **k: response)
            self.assertEqual(result.status, "error")
            self.assertEqual(cache.get(self.source.feed_url).payload, b"previous")

    def test_transient_errors_retry_but_malformed_feeds_do_not(self):
        for status, body, expected_calls in [(503, b"", 3), (429, b"", 3), (200, b"not XML", 1)]:
            with self.subTest(status=status):
                get = Mock(side_effect=lambda *args, **kwargs: FakeResponse([body], status=status))
                result = fetch_feed(self.source, request_get=get, sleep=Mock())
                self.assertEqual(result.status, "error")
                self.assertEqual(get.call_count, expected_calls)

    def test_budget_is_checked_during_streaming_and_response_closed(self):
        elapsed = [0]
        response = FakeResponse([])
        def chunks(chunk_size):
            elapsed[0] = 46
            yield b"slow response"
        response.iter_content = chunks
        with self.assertRaises(requests.Timeout):
            _download_feed(self.source.feed_url, 8, request_get=lambda *a, **k: response,
                           deadline=45, clock=lambda: elapsed[0])
        self.assertTrue(response.closed)

    def test_invalid_cache_is_ignored_and_pruning_preserves_user_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = FeedCache(root)
            cache.put(self.source.feed_url, CachedFeed(b"old", "bad\nvalidator"))
            self.assertEqual(cache.get(self.source.feed_url).etag, "")
            cache._path(self.source.feed_url).write_bytes(b"corrupt")
            self.assertIsNone(cache.get(self.source.feed_url))
            (root / "notes.txt").write_text("keep", encoding="utf-8")
            cache.prune([], max_bytes=0)
            self.assertTrue((root / "notes.txt").is_file())
            self.assertFalse(cache._path(self.source.feed_url).exists())

    def test_parser_filters_expired_unsafe_and_duplicate_articles(self):
        payload = b"""<?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Example</title>
          <item><title>Recent</title><link>https://example.com/recent</link>
            <pubDate>Wed, 30 Sep 2026 08:00:00 GMT</pubDate></item>
          <item><title>Duplicate</title><link>https://example.com/recent</link>
            <pubDate>Tue, 29 Sep 2026 08:00:00 GMT</pubDate></item>
          <item><title>Yesterday</title><link>https://example.com/yesterday</link>
            <pubDate>Tue, 29 Sep 2026 08:00:00 GMT</pubDate></item>
          <item><title>Midnight local</title><link>https://example.com/midnight</link>
            <pubDate>Tue, 29 Sep 2026 16:30:00 GMT</pubDate></item>
          <item><title>Unsafe</title><link>javascript:alert(1)</link>
            <pubDate>Wed, 30 Sep 2026 08:00:00 GMT</pubDate></item>
          <item><title>Expired</title><link>https://example.com/expired</link>
            <pubDate>Sat, 01 Aug 2026 08:00:00 GMT</pubDate></item>
        </channel></rss>"""

        articles = _parse_articles(
            self.source,
            payload,
            today=date(2026, 9, 30),
            retention_days=30,
            only_date=date(2026, 9, 30),
            minimum_articles=0,
        )

        self.assertEqual(
            [article.title for article in articles],
            ["Recent", "Midnight local"],
        )

    def test_download_rejects_oversized_response_and_closes_it(self):
        response = FakeResponse([], content_length=MAX_FEED_BYTES + 1)

        with self.assertRaises(ValueError):
            _download_feed(
                self.source.feed_url,
                timeout=1,
                request_get=lambda *args, **kwargs: response,
            )

        self.assertTrue(response.closed)


if __name__ == "__main__":
    unittest.main()

import unittest
from datetime import date, datetime, timedelta, timezone
from unittest.mock import Mock

from garss.fetch import _parse_articles, fetch_feed
from garss.fetch_pool import _collect_feeds
from garss.health import measure_new_articles, upstream_failures
from garss.models import Article, FeedResult, FeedSource
from garss.source_lifecycle import prepare, update


class FeedHealthTests(unittest.TestCase):
    now = datetime(2026, 10, 13, tzinfo=timezone.utc)
    source = FeedSource('a', 'A', '', 'https://feeds.test/rss')

    def response(self, payload):
        response = Mock(status_code=200, headers={})
        response.iter_content.return_value = [payload]
        return response

    def test_empty_feed_is_success_with_zero_observed_counts(self):
        result = fetch_feed(self.source, request_get=Mock(return_value=self.response(
            b'<rss version="2.0"><channel><title>Quiet</title></channel></rss>')))
        self.assertEqual(result.status, 'ok')
        self.assertEqual(result.health(), {'raw_entry_count': 0, 'valid_article_count': 0, 'drop_reasons': {}})
        self.assertIsNone(result.new_article_count)  # Unseen history is not a measured zero.

    def test_malformed_feed_has_error_without_invented_zero_metrics(self):
        result = fetch_feed(self.source, request_get=Mock(return_value=self.response(b'<html>Bad</html>')))
        self.assertEqual(result.status, 'error')
        self.assertEqual(result.health(), {})

    def test_each_dropped_entry_is_explained_and_valid_is_before_retention(self):
        def item(title, url, published='Tue, 13 Oct 2026 00:00:00 GMT'):
            return f'<item><title>{title}</title><link>{url}</link><pubDate>{published}</pubDate></item>'
        payload = ('<rss version="2.0"><channel><title>Feed</title>' + ''.join([
            item('Valid', 'https://test.example/a'),
            item('Duplicate', 'https://test.example/a?utm_source=rss'),
            item('No date', 'https://test.example/b', 'not a date'),
            item('Future', 'https://test.example/c', 'Tue, 13 Oct 2027 00:00:00 GMT'),
            item('Unsafe', 'javascript:alert(1)'), item('', 'https://test.example/d'),
            item('Old valid', 'https://test.example/e', 'Tue, 01 Jan 2020 00:00:00 GMT'),
        ]) + '</channel></rss>').encode()
        health = {}
        articles = _parse_articles(self.source, payload, today=date(2026, 10, 13), minimum_articles=0, health=health)
        self.assertEqual(len(articles), 1)
        self.assertEqual(health['raw_entry_count'], 7)
        self.assertEqual(health['valid_article_count'], 2)
        self.assertEqual(health['drop_reasons'], {
            'missing_or_invalid_date': 1, 'future_date': 1, 'unsafe_or_missing_url': 1,
            'missing_title': 1, 'duplicate_url': 1, 'outside_retention': 1,
        })
        self.assertEqual(sum(health['drop_reasons'].values()) + len(articles), health['raw_entry_count'])

    def test_coalesced_results_preserve_health_without_sharing_mutable_counts(self):
        second = FeedSource('b', 'B', '', self.source.feed_url)
        original = FeedResult(self.source, raw_entry_count=5, valid_article_count=4, drop_reasons={'missing_title': 1})
        results = _collect_feeds([self.source, second], 1, lambda _: original)
        self.assertEqual(results[0].health(), results[1].health())
        results[0].drop_reasons['missing_title'] = 2
        self.assertEqual(results[1].drop_reasons['missing_title'], 1)

    def test_no_new_or_empty_success_does_not_archive_quiet_source(self):
        config = {'sources': [{'id': 'a', 'feed_url': self.source.feed_url}]}
        states, _ = prepare(config, {}, self.now)
        old = Article('a', 'Quiet publisher', 'https://test.example/a', self.now - timedelta(days=90))
        last_new = old.published_at.isoformat().replace('+00:00', 'Z')
        states['a']['health'] = {'last_new_article_at': last_new}
        for days, articles in [(0, [old]), (1, []), (30, [])]:
            result = FeedResult(self.source, articles, raw_entry_count=len(articles), valid_article_count=len(articles), drop_reasons={})
            measure_new_articles([result], [old], states, self.now + timedelta(days=days))
            update(states, [result], self.now + timedelta(days=days))
            self.assertEqual(result.new_article_count, 0)
            self.assertEqual(states['a']['status'], 'active')
            self.assertEqual(states['a']['failures'], 0)
            self.assertEqual(states['a']['health']['last_new_article_at'], last_new)

    def test_new_count_uses_canonical_urls_and_failed_result_stays_unknown(self):
        old = Article('a', 'Old', 'https://test.example/a', self.now - timedelta(days=1))
        tracking = Article('a', 'Updated title', old.url + '?utm_source=rss', self.now)
        new = Article('a', 'New', 'https://test.example/b', self.now)
        result = FeedResult(self.source, [tracking, new, new])
        measure_new_articles([result], [old], {}, self.now)
        self.assertEqual(result.new_article_count, 1)
        self.assertEqual(result.last_new_article_at, self.now)
        failed = FeedResult(self.source, error='timeout')
        measure_new_articles([failed], [old], {}, self.now)
        self.assertIsNone(failed.new_article_count)

    def test_last_new_article_measures_observation_time_for_backfilled_old_post(self):
        old_post = Article('a', 'Newly found old post', 'https://test.example/backfill', self.now - timedelta(days=90))
        result = FeedResult(self.source, [old_post])
        measure_new_articles([result], [], {}, self.now)
        self.assertEqual(result.new_article_count, 1)
        self.assertEqual(result.last_new_article_at, self.now)
        self.assertNotEqual(result.last_new_article_at, old_post.published_at)

    def test_grouped_upstream_failures_include_legacy_404_evidence_and_do_not_mutate(self):
        config = {'sources': [{'id': str(i), 'feed_url': f'https://rsshub.v2fy.com/{i}'} for i in range(21)]}
        states = {str(i): {'status': 'archived', 'last_error': f'404 Client Error: Not Found for url: https://rsshub.v2fy.com/{i}'} for i in range(21)}
        groups = upstream_failures(config, states)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]['host'], 'rsshub.v2fy.com')
        self.assertEqual((groups[0]['http_status'], groups[0]['count'], groups[0]['archived_count']), (404, 21, 21))
        self.assertTrue(all(state['status'] == 'archived' for state in states.values()))

    def test_grouped_report_is_bounded_and_excludes_disabled_sources(self):
        config = {'sources': [{'id': str(i), 'feed_url': f'https://host{i // 110}.test/rss'} for i in range(2400)]}
        states = {str(i): {'status': 'error', 'last_error': 'HTTP 503', 'last_http_status': 503} for i in range(2400)}
        config['sources'][0]['enabled'] = False
        groups = upstream_failures(config, states)
        self.assertEqual(len(groups), 20)
        self.assertTrue(all(len(item['source_ids']) <= 100 for item in groups))
        self.assertTrue(all('0' not in item['source_ids'] for item in groups))


if __name__ == '__main__':
    unittest.main()

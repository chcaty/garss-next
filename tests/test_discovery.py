import copy
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock, patch

from garss.discovery import discover, parse_opml, MAX_CHECKS, MAX_CANDIDATES
from garss.models import Article, FeedResult, FeedSource
from garss.source_lifecycle import stamp


class DiscoveryTests(unittest.TestCase):
    now = datetime(2026, 10, 13, tzinfo=timezone.utc)
    config = {'sources': []}
    directory = {'url': 'https://directory.test/opml', 'page': 'https://directory.test', 'category': 'News'}

    def candidate(self, index, **kwargs):
        return {'id': f'candidate-{index}', 'title': f'Candidate {index}', 'description': '',
                'feed_url': f'https://candidate.test/{index}/rss', 'category': 'News', **kwargs}

    def result(self, item, articles=None, error=None):
        source = FeedSource(item['id'], item.get('title', ''), '', item['feed_url'])
        if articles is None:
            articles = [Article(source.id, 'Latest article', f'https://article.test/{source.id}', self.now)]
        return FeedResult(source, articles, error, raw_entry_count=len(articles), valid_article_count=len(articles), drop_reasons={})

    def opml(self, count=1):
        return ('<opml><body>' + ''.join(f'<outline text="Fresh {i}" xmlUrl="https://fresh.test/{i}/rss"/>' for i in range(count)) + '</body></opml>').encode()

    def test_recent_preview_has_three_safe_plain_titles_with_dates(self):
        def check(item):
            entries = [Article(item['id'], '<b>Title</b> <script>hidden</script>', f'https://article.test/{i}', self.now - timedelta(days=i)) for i in range(5)]
            entries.insert(0, Article(item['id'], 'Unsafe', 'javascript:bad', self.now))
            return self.result(item, entries)
        doc = discover(self.config, [self.directory], {}, self.now, download=lambda _: self.opml(), check=check)
        candidate = doc['candidates'][0]
        self.assertEqual(candidate['validation_status'], 'verified')
        self.assertEqual(len(candidate['recent_articles']), 3)
        self.assertEqual([item['url'] for item in candidate['recent_articles']], [f'https://article.test/{i}' for i in range(3)])
        self.assertTrue(all(item['title'] == 'Title' for item in candidate['recent_articles']))
        self.assertEqual(candidate['expires_at'], stamp(self.now + timedelta(days=14)))
        self.assertEqual(candidate['health']['latest_article_at'], stamp(self.now))
        self.assertNotIn('new_article_count', candidate['health'])

    def test_new_empty_or_malformed_feed_is_not_a_verified_candidate(self):
        for error, articles in [(None, []), ('response is not RSS or Atom', [])]:
            with self.subTest(error=error):
                doc = discover(self.config, [self.directory], {}, self.now, download=lambda _: self.opml(),
                               check=lambda item: self.result(item, articles, error))
                self.assertEqual(doc['candidates'], [])
                self.assertEqual(len(doc['rejected']), 1)

    def test_default_verifier_passes_date_and_bounded_fetch_budget(self):
        def fetch(source, **kwargs):
            return FeedResult(source, [Article(source.id, 'Latest', 'https://article.test/latest', self.now)])
        with patch('garss.discovery.fetch_feed', side_effect=fetch) as fetcher:
            doc = discover(self.config, [self.directory], {}, self.now, download=lambda _: self.opml())
        self.assertEqual(doc['checked_count'], 1)
        self.assertEqual(fetcher.call_args.kwargs['attempts'], 1)
        self.assertEqual(fetcher.call_args.kwargs['budget_seconds'], 15)
        self.assertEqual(fetcher.call_args.kwargs['today'].isoformat(), '2026-10-13')

    def test_ttl_revalidates_independently_of_directory_refresh(self):
        first = discover(self.config, [self.directory], {}, self.now, download=lambda _: self.opml(), check=self.result)
        # Simulate a directory refresh one day before verification expires.
        first['last_attempt_at'] = stamp(self.now + timedelta(days=13))
        calls = []
        unchanged = discover(self.config, [self.directory], first, self.now + timedelta(days=13),
                             download=lambda _: self.fail('Directory is not due'), check=lambda item: calls.append(item) or self.result(item))
        self.assertEqual(calls, [])
        refreshed = discover(self.config, [self.directory], unchanged, self.now + timedelta(days=14),
                             download=lambda _: self.fail('Directory is not due'), check=lambda item: calls.append(item) or self.result(item))
        self.assertEqual(len(calls), 1)
        self.assertEqual(refreshed['revalidation_checked_count'], 1)
        self.assertEqual(refreshed['exploration_checked_count'], 0)
        self.assertEqual(refreshed['candidates'][0]['verified_at'], stamp(self.now + timedelta(days=14)))

    def test_revalidation_failure_preserves_last_good_preview_then_retries_after_one_day(self):
        first = discover(self.config, [self.directory], {}, self.now, download=lambda _: self.opml(), check=self.result)
        before = copy.deepcopy(first)
        due = self.now + timedelta(days=14)
        failed = discover(self.config, [self.directory], first, due, download=lambda _: self.opml(),
                          check=lambda item: self.result(item, error='HTTP 503'))
        self.assertEqual(first, before)  # No mutation of previously published data.
        candidate = failed['candidates'][0]
        self.assertEqual(candidate['verified_at'], before['candidates'][0]['verified_at'])
        self.assertEqual(candidate['recent_articles'], before['candidates'][0]['recent_articles'])
        self.assertEqual(candidate['health'], before['candidates'][0]['health'])
        self.assertEqual(candidate['health_checked_at'], stamp(self.now))
        self.assertEqual(candidate['validation_status'], 'error')
        self.assertEqual(failed['checked_count'], 1)
        quiet = discover(self.config, [self.directory], failed, due + timedelta(hours=23),
                         check=lambda _: self.fail('Not due'), download=lambda _: self.fail('Directory not due'))
        self.assertEqual(quiet['checked_count'], 0)
        recovered = discover(self.config, [self.directory], quiet, due + timedelta(days=1), check=self.result)
        self.assertEqual(recovered['candidates'][0]['validation_status'], 'verified')
        self.assertNotIn('first_validation_failed_at', recovered['candidates'][0])
        self.assertEqual(recovered['rejected'], {})

    def test_empty_revalidation_keeps_preview_and_does_not_refresh_verification(self):
        first = discover(self.config, [self.directory], {}, self.now, download=lambda _: self.opml(), check=self.result)
        result = discover(self.config, [self.directory], first, self.now + timedelta(days=14),
                          download=lambda _: self.opml(), check=lambda item: self.result(item, []))
        self.assertEqual(result['candidates'][0]['validation_status'], 'empty')
        self.assertEqual(result['candidates'][0]['recent_articles'], first['candidates'][0]['recent_articles'])
        self.assertEqual(result['candidates'][0]['verified_at'], stamp(self.now))
        self.assertEqual(result['candidates'][0]['health']['valid_article_count'], 0)
        self.assertEqual(result['candidates'][0]['health']['raw_entry_count'], 0)
        self.assertEqual(result['candidates'][0]['health_checked_at'], stamp(self.now + timedelta(days=14)))

    def test_full_queue_still_explores_and_bounds_total_checks(self):
        old = [self.candidate(i, verified_at=stamp(self.now - timedelta(days=15))) for i in range(MAX_CANDIDATES)]
        seen = []
        doc = discover(self.config, [self.directory], {'candidates': old}, self.now,
                       download=lambda _: self.opml(40), check=lambda item: seen.append(item['feed_url']) or self.result(item))
        self.assertEqual(len(seen), MAX_CHECKS)
        self.assertEqual(doc['exploration_checked_count'], 15)
        self.assertEqual(doc['revalidation_checked_count'], 5)
        self.assertEqual(len(doc['candidates']), MAX_CANDIDATES)
        self.assertEqual(sum(item['feed_url'].startswith('https://fresh.test') for item in doc['candidates']), 15)
        self.assertEqual(len(old), MAX_CANDIDATES)

    def test_budget_spills_unused_slots_in_both_directions(self):
        for stale_count, fresh_count, expected_stale, expected_fresh in [(0, 40, 0, 20), (2, 40, 2, 18), (30, 2, 18, 2), (30, 0, 20, 0), (1, 1, 1, 1)]:
            with self.subTest(stale_count=stale_count, fresh_count=fresh_count):
                old = [self.candidate(i, verified_at=stamp(self.now - timedelta(days=20))) for i in range(stale_count)]
                doc = discover(self.config, [self.directory], {'candidates': old}, self.now,
                               download=lambda _: self.opml(fresh_count), check=self.result)
                self.assertEqual(doc['checked_count'], expected_stale + expected_fresh)
                self.assertEqual(doc['exploration_checked_count'], expected_fresh)
                self.assertEqual(doc['revalidation_checked_count'], expected_stale)
                self.assertLessEqual(doc['checked_count'], MAX_CHECKS)

    def test_failed_exploration_cannot_evict_full_good_queue(self):
        old = [self.candidate(i, verified_at=stamp(self.now)) for i in range(MAX_CANDIDATES)]
        doc = discover(self.config, [self.directory], {'candidates': old}, self.now,
                       download=lambda _: self.opml(40), check=lambda item: self.result(item, error='HTTP 404'))
        self.assertEqual(doc['candidates'], old)
        self.assertEqual(doc['checked_count'], MAX_CHECKS)

    def test_newly_admitted_candidates_do_not_evict_each_other_on_equal_timestamps(self):
        old = [self.candidate(i, verified_at=stamp(self.now), feed_url=f'https://z-last.test/{i}/rss') for i in range(MAX_CANDIDATES)]
        doc = discover(self.config, [self.directory], {'candidates': old}, self.now,
                       download=lambda _: self.opml(40), check=self.result)
        self.assertEqual(len(doc['candidates']), MAX_CANDIDATES)
        self.assertEqual(sum(item['feed_url'].startswith('https://fresh.test') for item in doc['candidates']), MAX_CHECKS)

    def test_directory_failure_keeps_count_last_success_and_candidates(self):
        old = self.candidate(1, verified_at=stamp(self.now))
        previous = {'candidates': [old], 'directories': [{**self.directory, 'feed_count': 10, 'last_success_at': stamp(self.now - timedelta(days=7))}]}
        doc = discover(self.config, [self.directory], previous, self.now,
                       download=Mock(side_effect=ValueError('Bad XML')), check=lambda _: self.fail('Fresh candidate'))
        self.assertEqual(doc['candidates'], [old])
        self.assertEqual(doc['directories'][0]['feed_count'], 10)
        self.assertEqual(doc['directories'][0]['last_success_at'], previous['directories'][0]['last_success_at'])
        self.assertEqual(doc['directories'][0]['status'], 'error')

    def test_invalid_expiry_and_rejection_timestamps_cannot_crash_or_suppress_checks(self):
        for value in ('not a date', '2026-10-13', '2999-01-01T00:00:00Z', None, {}, 42):
            with self.subTest(value=value):
                old = self.candidate(1, verified_at=value, expires_at=value)
                previous = {'candidates': [old], 'last_attempt_at': value,
                            'rejected': {'https://fresh.test/0/rss': {'checked_at': value}}}
                doc = discover(self.config, [self.directory], previous, self.now, download=lambda _: self.opml(), check=self.result)
                self.assertEqual(doc['checked_count'], 2)
                self.assertEqual(doc['candidates'][0]['expires_at'], stamp(self.now + timedelta(days=14)))

    def test_failed_new_feed_retries_at_thirty_days_and_seed_exception_is_preserved(self):
        for days, expected in [(29, 0), (30, 1)]:
            with self.subTest(days=days):
                previous = {'rejected': {'https://fresh.test/0/rss': {'checked_at': stamp(self.now - timedelta(days=days))}}}
                doc = discover(self.config, [self.directory], previous, self.now,
                               download=lambda _: self.opml(), check=self.result)
                self.assertEqual(doc['exploration_checked_count'], expected)
        seed = self.candidate(1)
        previous = {'rejected': {seed['feed_url']: {'checked_at': stamp(self.now)}}}
        seeded = discover(self.config, [], previous, self.now, seed_sources=[seed], check=self.result)
        self.assertEqual(seeded['exploration_checked_count'], 1)

    def test_failed_retention_requires_an_actual_failed_recheck_and_valid_start(self):
        old = self.candidate(1, verified_at=stamp(self.now - timedelta(days=60)),
                             validation_status='error', checked_at=stamp(self.now - timedelta(days=1)),
                             first_validation_failed_at=stamp(self.now - timedelta(days=30)))
        removed = discover(self.config, [], {'candidates': [old]}, self.now, check=lambda item: self.result(item, error='HTTP 404'))
        self.assertEqual(removed['candidates'], [])
        for value in ('invalid', stamp(self.now + timedelta(days=365)), None):
            with self.subTest(value=value):
                previous = {**old, 'first_validation_failed_at': value}
                kept = discover(self.config, [], {'candidates': [previous]}, self.now, check=lambda item: self.result(item, error='HTTP 404'))
                self.assertEqual(len(kept['candidates']), 1)
                self.assertEqual(kept['candidates'][0]['first_validation_failed_at'], stamp(self.now))

    def test_bad_previous_candidates_are_ignored_and_existing_catalog_is_never_returned(self):
        existing = self.candidate(1)
        previous = {'candidates': [None, {}, {'feed_url': 'javascript:bad'}, existing, self.candidate(2, verified_at=stamp(self.now))]}
        doc = discover({'sources': [existing]}, [], previous, self.now, check=self.result)
        self.assertEqual([item['id'] for item in doc['candidates']], ['candidate-2'])
        self.assertEqual(len(previous['candidates']), 5)

    def test_rejections_bounded_and_valid_opml_required(self):
        previous = {'rejected': {f'https://example.test/{i}': {'checked_at': stamp(self.now)} for i in range(700)}}
        doc = discover(self.config, [], previous, self.now)
        self.assertEqual(len(doc['rejected']), 500)
        for payload in (b'<!DOCTYPE x><opml/>', b'<html/>', b'not XML', b'<!ENTITY x "bad"><opml/>'):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                parse_opml(payload, self.directory)


if __name__ == '__main__':
    unittest.main()

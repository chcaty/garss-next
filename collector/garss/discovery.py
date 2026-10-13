"""Bounded OPML discovery. External data enters a review queue, never authored config."""
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict
from copy import deepcopy
import json
from datetime import timedelta
from hashlib import sha256
import xml.etree.ElementTree as ET
import requests
from .catalog import safe_http_url, feed_key
from .fetch import fetch_feed
from .health import observed_date
from .models import FeedResult, FeedSource
from .source_lifecycle import stamp
from .text import plain_summary
from .timezones import app_date

MAX_CANDIDATES = 100
MAX_CHECKS = 20
REVALIDATION_RESERVE = 5
VERIFICATION_TTL = timedelta(days=14)
FAILED_RETRY = timedelta(days=1)
FAILED_RETENTION = timedelta(days=30)


def parse_opml(payload, directory):
    if len(payload) > 2_000_000 or b'<!DOCTYPE' in payload.upper() or b'<!ENTITY' in payload.upper():
        raise ValueError('OPML too large or contains unsupported declarations')
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as error:
        raise ValueError(f'invalid OPML: {error}') from error
    if root.tag.lower() != 'opml':
        raise ValueError('response is not OPML')
    items = []
    for item in root.iter('outline'):
        url = item.get('xmlUrl', '').strip()
        try:
            key = feed_key(url)
        except ValueError:
            continue
        items.append({'id': 'discovered-' + sha256(key.encode()).hexdigest()[:16],
                      'title': (item.get('title') or item.get('text') or url).strip() or url,
                      'feed_url': url, 'category': item.get('category') or directory['category'],
                      'description': item.get('description', '')[:500], 'enabled': True,
                      'discovered_from': directory['page']})
        if len(items) >= 1000:
            break
    return items


def download_opml(url):
    with requests.get(url, timeout=(5, 15), stream=True) as response:
        response.raise_for_status()
        payload = bytearray()
        for chunk in response.iter_content(65536):
            payload.extend(chunk)
            if len(payload) > 2_000_000:
                raise ValueError('OPML exceeds size limit')
        return bytes(payload)


def _elapsed(value, now, duration):
    parsed = observed_date(value)
    # Invalid/future timestamps cannot suspend work indefinitely.
    return parsed is None or parsed > now or now - parsed >= duration


def _candidate_key(item):
    try:
        return feed_key(item['feed_url']) if isinstance(item, dict) else None
    except (KeyError, TypeError, ValueError, AttributeError):
        return None


def _due(item, now):
    if item.get('validation_status') in {'error', 'empty'}:
        return _elapsed(item.get('checked_at'), now, FAILED_RETRY)
    # Derive expiration from the last good check; do not trust persisted expires_at.
    return _elapsed(item.get('verified_at'), now, VERIFICATION_TTL)


def _samples(result):
    samples = []
    seen = set()
    for article in sorted(result.articles, key=lambda item: item.published_at, reverse=True):
        try:
            url = safe_http_url(article.url)
            title = plain_summary(article.title, limit=200)
            if len(url) > 2048 or not title or article.published_at.tzinfo is None or url in seen:
                continue
            samples.append({'title': title, 'url': url, 'published_at': stamp(article.published_at),
                            'date_inferred': article.date_inferred})
            seen.add(url)
        except (AttributeError, TypeError, ValueError):
            continue
        if len(samples) == 3:
            break
    return samples


def _verify(item, now, check):
    try:
        result = check(item) if check else fetch_feed(
            FeedSource(item['id'], item.get('title', item['feed_url']), item.get('description', ''),
                       item['feed_url'], item.get('allow_undated', False)),
            today=app_date(now), attempts=1, budget_seconds=15,
        )
        # Preserve the original test/integration callback contract (error or None).
        if not isinstance(result, FeedResult):
            return ('error', str(result)[:300], None, None) if result else ('verified', '', None, None)
        if result.error:
            return 'error', result.error[:300], None, None
        samples = _samples(result)
        health = result.health()
        if samples:
            health['latest_article_at'] = samples[0]['published_at']
            return 'verified', '', samples, health
        return 'empty', 'Feed contains no usable articles', samples, health
    except Exception as error:
        return 'error', str(error)[:300], None, None


def _balanced(items, saved, now):
    groups = defaultdict(list)
    for item in items:
        groups[item.get('category', '')].append(item)
    for group in groups.values():
        group.sort(key=lambda item: sha256((item.get('id', item['feed_url']) + stamp(now)[:10]).encode()).hexdigest())
    counts = defaultdict(int)
    for item in saved.values():
        counts[item.get('category', '')] += 1
    categories = sorted(groups, key=lambda category: (counts[category], sha256((category + stamp(now)[:10]).encode()).hexdigest()))
    work = []
    while any(groups.values()):
        for category in categories:
            if groups[category]:
                work.append(groups[category].pop(0))
    return work


def _oldest(item, now):
    timestamp = observed_date(item.get('discovered_at')) or observed_date(item.get('verified_at'))
    return timestamp.timestamp() if timestamp and timestamp <= now else float('-inf')


def discover(config, directories, previous, now, *, download=download_opml, check=None, seed_sources=()):
    existing = {feed_key(source['feed_url']) for source in config['sources']}
    document = deepcopy(previous) if isinstance(previous, dict) else {}
    candidates = document.get('candidates', [])
    saved = {}
    for item in candidates if isinstance(candidates, list) else []:
        key = _candidate_key(item)
        if key and key not in existing and len(saved) < MAX_CANDIDATES:
            saved.setdefault(key, item)
    rejected = document.get('rejected', {})
    rejected = {key: item for key, item in rejected.items() if isinstance(item, dict)} if isinstance(rejected, dict) else {}
    revision = sha256(json.dumps([directories, seed_sources], sort_keys=True).encode()).hexdigest()
    refresh = (document.get('directories_revision') != revision or
               _elapsed(document.get('last_attempt_at'), now,
                        timedelta(days=1 if document.get('directory_errors') else 7)))
    pool, seed_keys = {}, set()
    if refresh:
        document['last_attempt_at'] = stamp(now)
        errors, directory_states = [], []
        for item in seed_sources:
            key = _candidate_key(item)
            if key:
                seed_keys.add(key)
                if key not in existing:
                    pool[key] = dict(item)
        old_directories = document.get('directories', [])
        previous_directories = {item.get('url'): item for item in old_directories if isinstance(item, dict)} if isinstance(old_directories, list) else {}
        for directory in directories:
            try:
                items = parse_opml(download(directory['url']), directory)
                directory_states.append({**directory, 'status': 'ok', 'checked_at': stamp(now),
                                         'feed_count': len({feed_key(item['feed_url']) for item in items}),
                                         'last_success_at': stamp(now)})
                for item in items:
                    key = feed_key(item['feed_url'])
                    if key not in existing:
                        pool.setdefault(key, item)
            except Exception as error:
                errors.append({'directory': directory['page'], 'error': str(error)[:300]})
                old = previous_directories.get(directory['url'], {})
                last_success = old.get('last_success_at') or (old.get('checked_at') if old.get('status') == 'ok' else None)
                # Preserve the last known count and success time on a download failure.
                directory_states.append({**old, **directory, 'status': 'error', 'checked_at': stamp(now),
                                         'error': str(error)[:300], 'feed_count': old.get('feed_count', 0),
                                         **({'last_success_at': last_success} if last_success else {})})
        document.update(directories_revision=revision, directory_errors=errors, directories=directory_states)
    fresh = _balanced([item for key, item in pool.items() if key not in saved and
                       (key in seed_keys or key not in rejected or
                        _elapsed(rejected[key].get('checked_at'), now, FAILED_RETENTION))], saved, now)
    stale = sorted((item for item in saved.values() if _due(item, now)),
                   key=lambda item: (observed_date(item.get('checked_at')) or observed_date(item.get('verified_at')) or now - timedelta(days=36500)))
    # Total stays at 20. Each side may use spare slots; stale entries cannot starve exploration.
    recheck_count = min(REVALIDATION_RESERVE, len(stale), MAX_CHECKS)
    fresh_count = min(len(fresh), MAX_CHECKS - recheck_count)
    recheck_count = min(len(stale), MAX_CHECKS - fresh_count)
    work = [(item, False) for item in stale[:recheck_count]] + [(item, True) for item in fresh[:fresh_count]]
    with ThreadPoolExecutor(max_workers=4) as workers:
        outcomes = list(workers.map(lambda pair: _verify(pair[0], now, check), work))
    verified_new = []
    for (item, is_new), (status, error, samples, health) in zip(work, outcomes):
        key = feed_key(item['feed_url'])
        if status != 'verified':
            rejected[key] = {'checked_at': stamp(now), 'error': error}
            if not is_new:
                first_failed = observed_date(item.get('first_validation_failed_at'))
                if first_failed is None or first_failed > now:
                    first_failed = now
                item.update(validation_status=status, validation_error=error, checked_at=stamp(now),
                            first_validation_failed_at=stamp(first_failed))
                if health is not None:
                    # Keep last-good samples, but expose the current empty-feed observation.
                    item.update(health=health, health_checked_at=stamp(now))
                if now - first_failed >= FAILED_RETENTION:
                    saved.pop(key, None)
            continue
        accepted = {**item, 'validation_status': 'verified', 'checked_at': stamp(now),
                    'verified_at': stamp(now), 'expires_at': stamp(now + VERIFICATION_TTL)}
        accepted.setdefault('discovered_at', item.get('verified_at') or stamp(now))
        accepted.pop('validation_error', None)
        accepted.pop('first_validation_failed_at', None)
        if samples is not None:
            accepted['recent_articles'] = samples
            accepted['health'] = health
            accepted['health_checked_at'] = stamp(now)
        rejected.pop(key, None)
        if is_new:
            verified_new.append((key, accepted))
        else:
            saved[key] = accepted
    # Only a successfully verified new candidate may displace an existing candidate.
    # Failed/stale entries go first, then oldest discovered; failed directories alone evict none.
    admitted = set()
    for key, item in verified_new:
        if len(saved) >= MAX_CANDIDATES:
            oldest = min((existing_key for existing_key in saved if existing_key not in admitted), key=lambda existing_key: (
                saved[existing_key].get('validation_status') not in {'error', 'empty'},
                not _due(saved[existing_key], now), _oldest(saved[existing_key], now), existing_key))
            saved.pop(oldest)
        saved[key] = item
        admitted.add(key)
    document.update(candidates=list(saved.values()), rejected=dict(list(rejected.items())[-500:]),
                    checked_count=len(work), exploration_checked_count=fresh_count,
                    revalidation_checked_count=recheck_count, generated_at=stamp(now))
    return document

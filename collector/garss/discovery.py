"""Bounded OPML discovery. External data enters a review queue, never authored config."""
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from hashlib import sha256
from urllib.parse import urlsplit, urlunsplit
import xml.etree.ElementTree as ET
import requests
from .catalog import safe_http_url
from .fetch import fetch_feed
from .models import FeedSource
from .source_lifecycle import date, stamp

MAX_CANDIDATES = 100
MAX_CHECKS = 20

def feed_key(url):
    parsed = urlsplit(safe_http_url(url))
    return urlunsplit((parsed.scheme.lower(), parsed.netloc.lower(), parsed.path, parsed.query, ''))

def parse_opml(payload, directory):
    if len(payload) > 2_000_000 or b'<!DOCTYPE' in payload.upper() or b'<!ENTITY' in payload.upper():
        raise ValueError('OPML too large or contains unsupported declarations')
    root = ET.fromstring(payload)
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

def discover(config, directories, previous, now, *, download=download_opml, check=None):
    existing = {feed_key(source['feed_url']) for source in config['sources']}
    document = dict(previous or {})
    candidates = [item for item in document.get('candidates', []) if feed_key(item['feed_url']) not in existing][:MAX_CANDIDATES]
    document['candidates'] = candidates
    if document.get('last_attempt_at') and now - date(document['last_attempt_at']) < timedelta(days=1 if document.get('directory_errors') else 7):
        return document
    document['last_attempt_at'] = stamp(now)
    errors = []
    pool = {}
    for directory in directories:
        try:
            for item in parse_opml(download(directory['url']), directory):
                key = feed_key(item['feed_url'])
                if key not in existing:
                    pool.setdefault(key, item)
        except Exception as error:
            errors.append({'directory': directory['page'], 'error': str(error)[:300]})
    saved = {feed_key(item['feed_url']): item for item in candidates}
    rejected = document.get('rejected', {})
    # Retry failures after 30 days, so one bad feed does not monopolize every batch.
    work = [item for key, item in pool.items() if key not in saved and
            (key not in rejected or now - date(rejected[key]['checked_at']) >= timedelta(days=30))]
    # Alternate catalogs rather than taking every item from the first catalog.
    work.sort(key=lambda item: sha256((item['id'] + stamp(now)[:10]).encode()).hexdigest())
    work = work[:min(MAX_CHECKS, MAX_CANDIDATES - len(saved))]
    def verify(item):
        try:
            return (check(item) if check else fetch_feed(FeedSource(item['id'], item['title'], item['description'], item['feed_url']), attempts=1, budget_seconds=15).error)
        except Exception as error:
            return str(error)[:300]
    with ThreadPoolExecutor(max_workers=4) as workers:
        outcomes = list(workers.map(verify, work))
    for item, error in zip(work, outcomes):
        key = feed_key(item['feed_url'])
        if error:
            rejected[key] = {'checked_at': stamp(now), 'error': str(error)[:300]}
        else:
            saved[key] = {**item, 'verified_at': stamp(now)}
            rejected.pop(key, None)
    document.update(candidates=list(saved.values()), rejected=dict(list(rejected.items())[-500:]),
                    directory_errors=errors, checked_count=len(work), generated_at=stamp(now))
    return document

"""Strict five-day mobile projection; the collector's full history is untouched."""
import copy
import json
import shutil
from datetime import datetime, timedelta
from hashlib import sha256

from .timezones import app_date

DAYS = 5


def _identity(feeds, articles, today):
    # Collection timestamps alone do not require another mobile download.
    stable_feeds = [{key: value for key, value in feed.items() if key != 'collected_at'}
                    for feed in feeds['feeds']]
    content = [today.isoformat(), stable_feeds, feeds.get('source_aliases', {}), articles['articles']]
    return sha256(json.dumps(content, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:20]


def create_app_snapshot(root, feed_doc, article_doc, generated_at, previous=None):
    from .snapshot import write_json
    today = app_date(generated_at)
    cutoff = today - timedelta(days=DAYS - 1)
    articles = copy.deepcopy(article_doc)
    articles['articles'] = [item for item in articles['articles']
                           if cutoff <= app_date(datetime.fromisoformat(item['published_at'].replace('Z', '+00:00'))) <= today]
    ids = {item['id'] for item in articles['articles']}
    feeds = copy.deepcopy(feed_doc)
    for feed in feeds['feeds']:
        feed['article_count'] = sum(feed['id'] in item['source_ids'] for item in articles['articles'])
        if 'new_ids' in feed:
            feed['new_ids'] = [identity for identity in feed['new_ids'] if identity in ids]
            feed['new_count'] = len(feed['new_ids']) if feed.get('baseline_known') else None
    identity = _identity(feeds, articles, today)
    app_root = root / 'api/v1/app'
    folder = app_root / 'snapshots' / identity
    old_root = previous / 'api/v1/app' if previous else None
    old_meta = validate_app_snapshot(previous) if old_root and (old_root / 'meta.json').exists() else None
    if old_meta and old_meta['snapshot_id'] == identity:
        # Reuse exact immutable bytes, including their original generation time.
        shutil.copytree(old_root / 'snapshots' / identity, folder)
        generated = old_meta['generated_at']
    else:
        generated = generated_at.isoformat().replace('+00:00', 'Z')
        write_json(folder / 'feeds.json', feeds)
        write_json(folder / 'articles.json', articles)
        files = {}
        for name in ('feeds.json', 'articles.json'):
            data = (folder / name).read_bytes()
            files[name] = {'bytes': len(data), 'sha256': sha256(data).hexdigest()}
        write_json(folder / 'manifest.json', {
            'api_version': '1.0', 'snapshot_id': identity, 'generated_at': generated,
            'retention_days': DAYS, 'timezone': 'Asia/Shanghai', 'window_start': cutoff.isoformat(),
            'window_end': today.isoformat(), 'feeds_endpoint': './feeds.json',
            'articles_endpoint': './articles.json', 'files': files})
    if old_meta and old_meta['snapshot_id'] != identity:
        old_id = old_meta['snapshot_id']
        shutil.copytree(old_root / 'snapshots' / old_id, app_root / 'snapshots' / old_id)
    # Pointer is written last. The enclosing fresh tree is published atomically by
    # the existing compare-and-swap data commit and Pages artifact deployment.
    write_json(app_root / 'meta.json', {
        'api_version': '1.0', 'snapshot_id': identity, 'generated_at': generated,
        'snapshot_endpoint': f'./snapshots/{identity}/manifest.json',
        'retention_days': DAYS, 'minimum_articles_per_source': 0,
        'timezone': 'Asia/Shanghai', 'window_start': cutoff.isoformat(), 'window_end': today.isoformat()})
    return identity


def validate_app_snapshot(root):
    folder = root / 'api/v1/app'
    meta = json.loads((folder / 'meta.json').read_text(encoding='utf-8'))
    identity = meta['snapshot_id']
    if len(identity) != 20 or any(char not in '0123456789abcdef' for char in identity):
        raise ValueError('Invalid mobile snapshot ID')
    snapshot = folder / 'snapshots' / identity
    manifest = json.loads((snapshot / 'manifest.json').read_text(encoding='utf-8'))
    for key in ('snapshot_id', 'generated_at', 'retention_days', 'timezone', 'window_start', 'window_end'):
        if meta[key] != manifest[key]:
            raise ValueError('Inconsistent mobile snapshot')
    if meta['retention_days'] != DAYS or meta['timezone'] != 'Asia/Shanghai':
        raise ValueError('Invalid mobile retention policy')
    documents = {}
    for name in ('feeds.json', 'articles.json'):
        data = (snapshot / name).read_bytes()
        if manifest['files'][name] != {'bytes': len(data), 'sha256': sha256(data).hexdigest()}:
            raise ValueError('Mobile snapshot integrity mismatch')
        documents[name] = json.loads(data)
        if documents[name]['generated_at'] != meta['generated_at']:
            raise ValueError('Mixed mobile snapshot')
    today = datetime.fromisoformat(meta['window_end']).date()
    if meta['window_start'] != (today - timedelta(days=DAYS - 1)).isoformat():
        raise ValueError('Invalid mobile window')
    for item in documents['articles.json']['articles']:
        day = app_date(datetime.fromisoformat(item['published_at'].replace('Z', '+00:00'))).isoformat()
        if not meta['window_start'] <= day <= meta['window_end']:
            raise ValueError('Article outside mobile window')
    if _identity(documents['feeds.json'], documents['articles.json'], today) != identity:
        raise ValueError('Mobile snapshot content identity mismatch')
    return meta

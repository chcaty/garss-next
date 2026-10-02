"""Bounded article snapshots. Source relations remain separate from article identity."""
import json
from dataclasses import replace
from hashlib import sha256
from pathlib import Path

from .article_identity import article_key


def write_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')


def consolidate(results):
    unique = {}
    for result in results:
        for article in result.articles:
            key = article_key(article.url)
            value = unique.get(key)
            if value is None:
                value = article.as_dict()
                value.update(id=sha256(key.encode()).hexdigest()[:20], source_ids=[], legacy_ids=[])
                unique[key] = value
            if article.source_id not in value['source_ids']:
                value['source_ids'].append(article.source_id)
            if article.id not in value['legacy_ids']:
                value['legacy_ids'].append(article.id)
            if not value['summary'] and article.summary:
                value['summary'] = article.summary
            if not value['image_url'] and article.image_url:
                value['image_url'] = article.image_url
    return sorted(unique.values(), key=lambda item: item['published_at'], reverse=True)


def expand_history(articles):
    """Load one article into each source list without losing its source associations."""
    from datetime import datetime
    from .models import Article
    result = []
    for item in articles:
        try:
            article = Article(item['source_id'], item['title'], item['url'],
                              datetime.fromisoformat(item['published_at'].replace('Z', '+00:00')),
                              item.get('summary', ''), item.get('image_url', ''))
            result.extend(replace(article, source_id=source) for source in item.get('source_ids', [article.source_id]))
        except (KeyError, TypeError, ValueError):
            continue
    return result


def create_snapshot(root: Path, results, config, generated_at, *, code_revision='local', source_revision='local'):
    generated = generated_at.isoformat().replace('+00:00', 'Z')
    articles = consolidate(results)
    counts = {}
    for article in articles:
        for source in article['source_ids']:
            counts[source] = counts.get(source, 0) + 1
    by_id = {result.source.id: result for result in results}
    feeds = []
    for item in config['sources']:
        result = by_id.get(item['id'])
        feeds.append({**item, 'status': 'disabled' if not item.get('enabled', True) else result.status if result else 'error',
                      'article_count': counts.get(item['id'], 0),
                      'error': result.error if result else None})
    feed_doc = {'api_version': '1.0', 'generated_at': generated, 'feeds': feeds}
    article_doc = {'api_version': '1.0', 'generated_at': generated, 'articles': articles}
    identity = sha256(json.dumps([feed_doc, article_doc], sort_keys=True).encode()).hexdigest()[:20]
    folder = root / 'api/v1/snapshots' / identity
    write_json(folder / 'feeds.json', feed_doc)
    write_json(folder / 'articles.json', article_doc)
    files = {}
    for name in ('feeds.json', 'articles.json'):
        data = (folder / name).read_bytes()
        files[name] = {'bytes': len(data), 'sha256': sha256(data).hexdigest()}
    write_json(folder / 'manifest.json', {'api_version': '1.0', 'snapshot_id': identity,
               'generated_at': generated, 'feeds_endpoint': './feeds.json', 'articles_endpoint': './articles.json', 'files': files})
    write_json(root / 'api/index.json', {'current_version': 'v1', 'versions': {'v1': './v1/meta.json'}})
    write_json(root / 'api/v1/meta.json', {'api_version': '1.0', 'generated_at': generated,
               'snapshot_id': identity, 'snapshot_endpoint': f'./snapshots/{identity}/manifest.json',
               'feeds_endpoint': './feeds.json', 'articles_endpoint': './articles.json',
               'retention_days': 30, 'minimum_articles_per_source': 5,
               'sources_endpoint': './sources.json', 'code_revision': code_revision, 'source_revision': source_revision})
    write_json(root / 'api/v1/feeds.json', feed_doc)
    write_json(root / 'api/v1/articles.json', article_doc)
    write_json(root / 'api/v1/sources.json', config)
    return identity


def validate_snapshot(root: Path):
    meta = json.loads((root / 'api/v1/meta.json').read_text(encoding='utf-8'))
    identity = meta['snapshot_id']
    if len(identity) != 20 or any(char not in '0123456789abcdef' for char in identity):
        raise ValueError('Invalid snapshot ID')
    folder = root / 'api/v1/snapshots' / identity
    manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
    if manifest['snapshot_id'] != identity or manifest['generated_at'] != meta['generated_at']:
        raise ValueError('Inconsistent snapshot')
    for name in ('feeds.json', 'articles.json'):
        data = (folder / name).read_bytes()
        if manifest['files'][name] != {'bytes': len(data), 'sha256': sha256(data).hexdigest()}:
            raise ValueError('Snapshot integrity mismatch')
    articles = json.loads((folder / 'articles.json').read_text(encoding='utf-8'))['articles']
    keys = [article_key(item['url']) for item in articles]
    if len(keys) != len(set(keys)):
        raise ValueError('Duplicate article identity')
    return meta

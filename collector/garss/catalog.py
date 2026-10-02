"""Source configuration independent of generated pages and article history."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

from .models import FeedSource


def safe_http_url(value: str) -> str:
    value = value.strip()
    uri = urlsplit(value)
    if uri.scheme.lower() not in {'http', 'https'} or not uri.hostname or uri.username or uri.password:
        raise ValueError('Expected a public HTTP(S) URL without embedded credentials')
    if any(ord(char) < 32 for char in value):
        raise ValueError('URL contains control characters')
    return value


def load_sources(path: Path) -> dict:
    config = json.loads(path.read_text(encoding='utf-8'))
    if config.get('schema_version') != '1.0' or not isinstance(config.get('sources'), list):
        raise ValueError('Unsupported source configuration')
    ids = set()
    for item in config['sources']:
        for key in ('id', 'title', 'description', 'category', 'feed_url'):
            if not isinstance(item.get(key), str):
                raise ValueError(f'Missing text field: {key}')
        if not re.fullmatch(r'[A-Za-z0-9_-]+', item['id']) or item['id'] in ids:
            raise ValueError('Duplicate or invalid source ID')
        ids.add(item['id'])
        if not item['title'].strip() or not item['category'].strip():
            raise ValueError('Source title and category are required')
        safe_http_url(item['feed_url'])
        for key in ('recheck_requested_at', 'discovered_from'):
            if key in item and not isinstance(item[key], str):
                raise ValueError(f'{key} must be a string')
        if not isinstance(item.get('allow_undated', False), bool):
            raise ValueError('allow_undated must be boolean')
        if not isinstance(item.get('enabled', True), bool):
            raise ValueError('enabled must be boolean')
    return config


def feed_sources(config: dict) -> list[FeedSource]:
    return [FeedSource(item['id'], item['title'], item['description'], item['feed_url'], item.get('allow_undated', False))
            for item in config['sources'] if item.get('enabled', True)]

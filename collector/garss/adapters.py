"""Normalize the supplied web-monitor parsers behind bounded, injected transport."""
import json
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path

from .catalog import safe_http_url
from .models import Article
from .text import plain_summary
from . import reference_parsers as reference

ADAPTERS = json.loads(Path(__file__).with_name('source_adapters.json').read_text(encoding='utf-8'))


def parse_adapter(source, payload, now=None, fetch_json=None):
    now = now or datetime.now(timezone.utc)
    adapter = ADAPTERS[source.adapter]
    captured = []
    secondary_errors = []

    def read_json(url, **kwargs):
        if url == adapter['url']:
            value = json.loads(payload)
        elif source.adapter == 'hn' and re.fullmatch(r'https://hacker-news\.firebaseio\.com/v0/item/\d+\.json', url) and fetch_json:
            try:
                value = fetch_json(url)
            except Exception as error:
                secondary_errors.append(str(error))
                raise
        else:
            raise ValueError('Unexpected adapter endpoint')
        captured.append(value)
        return value

    parser = getattr(reference, adapter['parser'])
    reader = (lambda *args, **kwargs: payload.decode('utf-8', errors='replace')) if adapter['family'] == 'core' else read_json
    if source.adapter == 'bilibili':
        data = json.loads(payload)
        if data.get('code') != 0 or not isinstance(data.get('data', {}).get('list'), list):
            raise ValueError('Bilibili response is unavailable')
    rows = parser(reader)
    if secondary_errors:
        raise ValueError('Hacker News item request failed; preserving previous complete results')
    if not rows:
        raise ValueError('Adapter returned no recognized entries')
    raw_by_key = {}

    def index_raw(value, depth=0):
        if depth > 8:
            return
        if isinstance(value, list):
            for item in value[:1000]:
                index_raw(item, depth + 1)
        elif isinstance(value, dict):
            for key in ('id', 'short_id', 'question_id', 'bvid'):
                if key in value:
                    raw_by_key[str(value[key])] = value
            for item in value.values():
                if isinstance(item, (dict, list)):
                    index_raw(item, depth + 1)

    for value in captured:
        index_raw(value)
    articles, seen = [], set()
    for position, row in enumerate(rows[:60], 1):
        title = str(row.get('title') or row.get('repo') or row.get('keyword') or row.get('code') or '').strip()
        try:
            url = safe_http_url(str(row.get('url') or ''))
        except ValueError:
            continue
        if not title or url in seen:
            continue
        raw = raw_by_key.get(str(row.get('key')), {})
        raw_time = next((raw.get(key) for key in ('published_at', 'created_at', 'creation_date', 'time') if raw.get(key)), None)
        raw_time = raw_time or row.get('created') or row.get('pubdate') or row.get('published')
        published, inferred = now, True
        try:
            if raw_time:
                published = (datetime.fromtimestamp(float(raw_time), timezone.utc) if isinstance(raw_time, (int, float)) or str(raw_time).isdigit()
                             else datetime.fromisoformat(str(raw_time).replace('Z', '+00:00')))
                if published.tzinfo is None:
                    published = published.replace(tzinfo=timezone(timedelta(hours=8)) if source.adapter == 'gossip' else timezone.utc)
                inferred = False
        except (ValueError, TypeError, OverflowError, OSError):
            published = now
        if published > now:
            continue
        image = str(row.get('cover') or row.get('avatar') or '')
        try:
            image = safe_http_url(image) if image else ''
        except ValueError:
            image = ''
        skip = {'key','title','repo','keyword','url','summary','desc','description','cover','avatar','created','pubdate','published','time_text'}
        metadata = {key: value for key, value in row.items() if key not in skip and isinstance(value, (str,int,float,bool)) and value != ''}
        heat = row.get('heat_num') or row.get('hot_num')
        if source.adapter in {'weibo_hot','toutiao','baidu_pc'} and heat:
            metadata['heat'] = heat
        extra = str(row.get('extra') or '')
        if match := re.search(r'评分\s*([\d.]+)', extra):
            metadata['rating'] = float(match[1])
        if source.adapter in {'hn','lobsters','stackoverflow'}:
            if match := re.search(r'▲(-?\d+)', extra): metadata['score'] = int(match[1])
        if match := re.search(r'(?:💬|答)\s*(\d+)', extra):
            metadata['answers' if source.adapter == 'stackoverflow' else 'replies'] = int(match[1])
        if source.adapter == 'sspai': metadata['replies'] = row.get('comments', 0)
        if source.adapter == 'bilibili': metadata['author'] = row.get('owner', '')
        if source.adapter == 'juejin' and heat: metadata['views'] = heat
        if adapter['content_type'] != 'article' or 'rank' in row:
            metadata['rank'] = row.get('rank', position)
        articles.append(Article(source.id, title[:500], url, published,
                                plain_summary(str(row.get('summary') or row.get('desc') or row.get('description') or '')),
                                image, inferred, adapter['content_type'], metadata))
        seen.add(url)
    if not articles:
        raise ValueError('Adapter returned no valid entries')
    return articles

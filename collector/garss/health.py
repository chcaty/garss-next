"""Optional, observational health data; never changes source configuration."""
from collections import defaultdict
from datetime import datetime
import re
from urllib.parse import urlsplit

from .article_identity import article_key


def observed_date(value):
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        return parsed if parsed.tzinfo is not None else None
    except (AttributeError, TypeError, ValueError, OverflowError):
        return None


def measure_new_articles(results, previous_articles, states, now):
    """Count newly seen URLs against the previous retained snapshot, before merging."""
    known = defaultdict(set)
    for article in previous_articles:
        known[article.source_id].add(article_key(article.url))
    for result in results:
        previous = states.get(result.source.id, {}).get('health', {})
        last_new = observed_date(previous.get('last_new_article_at'))
        if not result.error:
            new = {article_key(article.url): article for article in result.articles
                   if article_key(article.url) not in known[result.source.id]}
            result.new_article_count = len(new)
            if new:
                # This is when collection found a new URL, not its publication date.
                last_new = now
        result.last_new_article_at = last_new


def upstream_failures(config, states):
    """Group observed failures by host and HTTP status, without guessing root causes."""
    groups = defaultdict(list)
    for source in config['sources']:
        state = states.get(source['id'], {})
        error = state.get('last_error')
        if not error or not source.get('enabled', True):
            continue
        status = state.get('last_http_status')
        if not isinstance(status, int):
            # Older snapshots predate structured HTTP observations.
            match = re.search(r'\b([45]\d\d)\b(?: Client Error| Server Error)|\bHTTP\s+([45]\d\d)\b', str(error))
            status = int(next(part for part in match.groups() if part)) if match else None
        host = urlsplit(source['feed_url']).hostname
        groups[(host, status)].append(source['id'])
    grouped = []
    for (host, status), ids in groups.items():
        if len(ids) < 2:
            continue
        grouped.append({'host': host, 'http_status': status, 'count': len(ids),
                        'archived_count': sum(states[source_id].get('status') == 'archived' for source_id in ids),
                        'source_ids': sorted(ids)[:100]})
    return sorted(grouped, key=lambda item: (-item['count'], item['host'] or '', item['http_status'] or 0))[:20]

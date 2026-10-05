"""Collect public RSS into a fresh output tree; never modify source files."""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from dataclasses import replace
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'collector'))
from garss.catalog import load_sources, feed_sources
from garss.feed_cache import FeedCache
from garss.fetch_pool import fetch_all
from garss.history import merge_recent_history
from garss.models import FeedResult
from garss.snapshot import (
    create_snapshot, expand_history, read_previous_document,
    retain_previous_snapshot, validate_snapshot, write_json,
)
from garss.source_lifecycle import prepare, update, effective_config, stamp
from garss.sync_log import publication_log
from garss.discovery import discover
from garss.timezones import app_date


def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources', type=Path, default=ROOT / 'sources.json')
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--code-revision', default='local')
    parser.add_argument('--source-revision', default='local')
    return parser.parse_args()


def collect(args):
    if args.output.exists():
        raise ValueError('Output must be a new directory')
    config = load_sources(args.sources)
    old = expand_history(read_previous_document(args.previous, 'articles.json', {'articles': []})['articles'])
    aliases = config.get('source_aliases', {})
    old = [replace(article, source_id=aliases.get(article.source_id, article.source_id)) for article in old]
    now = datetime.now(timezone.utc)
    started_at = now
    states, due = prepare(config, read_previous_document(args.previous, 'source-state.json', {}).get('sources', {}), now)
    sources = feed_sources({'sources': due})
    if args.offline:
        results = [FeedResult(source, error='Migration seed; waiting for first live collection') for source in sources]
    else:
        cache = FeedCache(ROOT / '.cache/feed-responses')
        results = fetch_all(sources, fetch_date=app_date(now), workers=16, cache=cache,
                            bootstrap_ids=[source.id for source in sources], retention_days=30)
        cache.prune(source.feed_url for source in sources)
        active_results = [result for result in results if states[result.source.id]['status'] != 'archived']
        if active_results and all(result.error for result in active_results):
            raise RuntimeError('All enabled sources failed; previous data is preserved')
    run_results = list(results)
    if not args.offline:
        update(states, results, now)
    effective = effective_config(config, states)
    # Archived sources leave the reading catalog but stay in authored configuration.
    results = [result for result in results if states[result.source.id]['status'] != 'archived']
    results = merge_recent_history(results, old, app_date(now), 30)
    create_snapshot(args.output, results, effective, now,
                    code_revision=args.code_revision, source_revision=args.source_revision)
    write_json(args.output / 'api/v1/sources.json', config)
    write_json(args.output / 'api/v1/source-state.json', {'generated_at': stamp(now), 'sources': states,
               'policy': {'failures': 3, 'duration_hours': 24, 'retry_days': 7}})
    write_json(args.output / 'api/v1/source-archive.json', {'generated_at': stamp(now), 'sources': [
        {**source, **states[source['id']]} for source in config['sources'] if states[source['id']]['status'] == 'archived']})
    discovery = read_previous_document(args.previous, 'source-discovery.json', {})
    if not args.offline:
        settings = json.loads((ROOT / 'discovery-sources.json').read_text(encoding='utf-8'))
        discovery = discover(config, settings['directories'], discovery, now, seed_sources=settings.get('seed_sources', []))
    write_json(args.output / 'api/v1/source-discovery.json', discovery)
    # A bounded publication ledger; failed workflows remain discoverable in Actions.
    if not args.offline:
        finished = datetime.now(timezone.utc)
        article_count = len(json.loads((args.output / 'api/v1/articles.json').read_text(encoding='utf-8'))['articles'])
        write_json(args.output / 'api/v1/sync.json', publication_log(read_previous_document(args.previous, 'sync.json', {}),
                   run_results, states, started_at, finished, article_count, args.code_revision,
                   os.environ.get('GITHUB_RUN_ID', '')))
    # Keep at most the current and immediately previous immutable snapshot.
    retain_previous_snapshot(args.output, args.previous)
    validate_snapshot(args.output)
    print(f'Collected {sum(len(result.articles) for result in results)} source entries into a validated snapshot')


def main():
    collect(parse_arguments())


if __name__ == '__main__':
    main()

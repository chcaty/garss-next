"""Collect public RSS into a fresh output tree; never modify source files."""
import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'collector'))
from garss.catalog import load_sources, feed_sources
from garss.feed_cache import FeedCache
from garss.fetch_pool import fetch_all
from garss.history import merge_recent_history
from garss.models import FeedResult
from garss.snapshot import create_snapshot, expand_history, validate_snapshot
from garss.timezones import app_date


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources', type=Path, default=ROOT / 'sources.json')
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--code-revision', default='local')
    parser.add_argument('--source-revision', default='local')
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Output must be a new directory')
    config = load_sources(args.sources)
    sources = feed_sources(config)
    old = []
    if args.previous and (args.previous / 'api/v1/articles.json').exists():
        old = expand_history(json.loads((args.previous / 'api/v1/articles.json').read_text(encoding='utf-8'))['articles'])
    now = datetime.now(timezone.utc)
    if args.offline:
        results = [FeedResult(source, error='Migration seed; waiting for first live collection') for source in sources]
    else:
        cache = FeedCache(ROOT / '.cache/feed-responses')
        results = fetch_all(sources, fetch_date=app_date(now), workers=16, cache=cache,
                            bootstrap_ids=[source.id for source in sources], retention_days=30)
        cache.prune(source.feed_url for source in sources)
        if sources and all(result.error for result in results):
            raise RuntimeError('All enabled sources failed; previous data is preserved')
    results = merge_recent_history(results, old, app_date(now), 30)
    create_snapshot(args.output, results, config, now,
                    code_revision=args.code_revision, source_revision=args.source_revision)
    # Keep at most the current and immediately previous immutable snapshot.
    if args.previous and (args.previous / 'api/v1/meta.json').exists():
        previous = validate_snapshot(args.previous)['snapshot_id']
        source = args.previous / 'api/v1/snapshots' / previous
        dest = args.output / 'api/v1/snapshots' / previous
        if not dest.exists():
            shutil.copytree(source, dest)
    validate_snapshot(args.output)
    print(f'Collected {sum(len(result.articles) for result in results)} source entries into a validated snapshot')


if __name__ == '__main__':
    main()

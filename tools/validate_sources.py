"""Schema validation everywhere; live validation only for enabled changed URLs."""
import argparse
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'collector'))
from garss.catalog import load_sources, feed_sources
from garss.fetch import fetch_feed

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path)
    args = parser.parse_args()
    config = load_sources(ROOT / 'sources.json')
    if args.base:
        baseline = json.loads(args.base.read_text(encoding='utf-8'))
        urls = {item['feed_url'] for item in baseline['sources'] if item.get('enabled', True)}
        for source in feed_sources(config):
            if source.feed_url not in urls:
                result = fetch_feed(source, attempts=1, budget_seconds=15)
                if result.error:
                    raise ValueError(f'RSS validation failed for {source.id}: {result.error}')
    print('Source configuration valid')

"""Exercise the collection entry point without network or a public repository."""
import importlib.util
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

from garss.models import Article, FeedResult, FeedSource
from garss.snapshot import create_snapshot, validate_snapshot

spec = importlib.util.spec_from_file_location('collect_tool', Path(__file__).resolve().parents[1] / 'tools/collect.py')
collect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collect)


class CollectionTests(unittest.TestCase):
    now = datetime(2026, 10, 5, 0, 0, tzinfo=timezone.utc)
    source = FeedSource('current', 'Current', '', 'https://example.com/feed')
    config = {'schema_version': '1.0', 'sources': [
        {'id': 'current', 'title': 'Current', 'description': '', 'category': 'Tech',
         'feed_url': source.feed_url, 'enabled': True}], 'source_aliases': {'old': 'current'}}

    def invoke(self, root, *arguments):
        config = root / 'sources.json'
        config.write_text(json.dumps(self.config), encoding='utf-8')
        (root / 'discovery-sources.json').write_text('{"directories":[]}', encoding='utf-8')
        with patch.object(collect, 'ROOT', root), patch.object(collect, 'datetime') as clock, \
                patch('sys.argv', ['collect', '--sources', str(config), *map(str, arguments)]), \
                patch('builtins.print'):
            clock.now.return_value = self.now
            collect.main()

    def test_offline_seed_remaps_history_and_retains_only_previous_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            previous = root / 'previous'
            old_source = FeedSource('old', 'Old', '', self.source.feed_url)
            article = Article('old', 'Saved content', 'https://example.com/post', self.now, 'Summary')
            identity = create_snapshot(previous, [FeedResult(old_source, [article])],
                                       {'sources': [{'id': 'old', 'title': 'Old', 'feed_url': old_source.feed_url}]}, self.now)
            (previous / 'api/v1/snapshots/unrelated').mkdir()
            output = root / 'output'
            self.invoke(root, '--offline', '--previous', previous, '--output', output,
                        '--code-revision', 'code', '--source-revision', 'source')
            meta = validate_snapshot(output)
            self.assertEqual({p.name for p in (output / 'api/v1/snapshots').iterdir()}, {identity, meta['snapshot_id']})
            self.assertEqual(meta['code_revision'], 'code')
            self.assertEqual(meta['source_revision'], 'source')
            documents = {p.name: json.loads(p.read_text(encoding='utf-8'))
                         for p in (output / 'api/v1').glob('*.json')}
            self.assertEqual(documents['sources.json'], self.config)
            self.assertEqual(documents['articles.json']['articles'][0]['source_ids'], ['current'])
            self.assertEqual(documents['articles.json']['articles'][0]['summary'], 'Summary')
            self.assertEqual(documents['source-state.json']['policy'], {'failures': 3, 'duration_hours': 24, 'retry_days': 7})
            self.assertFalse((output / 'api/v1/sync.json').exists())

    def test_all_active_failures_stop_before_writing_or_discovery(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'output'
            with patch.object(collect, 'FeedCache'), \
                    patch.object(collect, 'fetch_all', return_value=[FeedResult(self.source, error='offline')]), \
                    patch.object(collect, 'discover') as discover:
                with self.assertRaisesRegex(RuntimeError, 'All enabled sources failed'):
                    self.invoke(root, '--output', output)
                self.assertFalse(output.exists())
                discover.assert_not_called()

    def test_live_collection_writes_health_discovery_and_publication_ledger(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'output'
            article = Article('current', 'Article', 'https://example.com/post', self.now)
            with patch.object(collect, 'FeedCache'), \
                    patch.object(collect, 'fetch_all', return_value=[FeedResult(self.source, [article])]), \
                    patch.object(collect, 'discover', return_value={'candidates': []}) as discover, \
                    patch.dict('os.environ', {'GITHUB_RUN_ID': '123'}):
                self.invoke(root, '--output', output)
                discover.assert_called_once()
            validate_snapshot(output)
            feeds = json.loads((output / 'api/v1/feeds.json').read_text(encoding='utf-8'))
            self.assertEqual(feeds['feeds'][0]['collection_status'], 'active')
            ledger = json.loads((output / 'api/v1/sync.json').read_text(encoding='utf-8'))
            self.assertEqual(ledger['runs'][0]['workflow_run_id'], '123')
            self.assertEqual(ledger['runs'][0]['article_count'], 1)
            self.assertEqual(ledger['runs'][0]['checked'], 1)

    def test_existing_output_is_rejected_without_modification(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'output'
            output.mkdir()
            marker = output / 'keep.txt'
            marker.write_text('keep', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'new directory'):
                self.invoke(root, '--offline', '--output', output)
            self.assertEqual(marker.read_text(encoding='utf-8'), 'keep')

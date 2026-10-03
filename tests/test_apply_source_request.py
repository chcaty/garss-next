import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from garss.source_request import source_hash, MARKER

spec = importlib.util.spec_from_file_location('apply_source_request', Path(__file__).resolve().parents[1]/'tools/apply_source_request.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ApplySourceRequestTests(unittest.TestCase):
    def setUp(self):
        self.source = {'id': 'a', 'title': 'Source', 'description': '', 'category': 'Tech', 'feed_url': 'https://example.com/rss', 'enabled': True}
        self.config = {'schema_version': '1.0', 'repository': {'owner': 'owner', 'name': 'repo'}, 'sources': [self.source]}
        self.request = {'version': 1, 'repository': 'owner/repo', 'operations': [{'id': 'a', 'before': source_hash(self.source), 'set': {'enabled': False}}]}
        self.issue = {'state': 'open', 'user': {'login': 'owner'}, 'body': MARKER+'\n```json\n'+json.dumps(self.request)+'\n```'}
        self.event = {'repository': {'full_name': 'owner/repo', 'owner': {'login': 'owner'}}, 'sender': {'login': 'owner'}, 'issue': self.issue}

    def test_preparation_writes_validated_config_and_exact_baseline(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder);(root/'sources.json').write_text(json.dumps(self.config), encoding='utf-8')
            self.assertEqual(module.prepare(self.event, self.issue, root), 'changed')
            self.assertEqual(json.loads((root/'build/base-sources.json').read_text(encoding='utf-8')), self.config)
            updated = json.loads((root/'sources.json').read_text(encoding='utf-8'))
            self.assertFalse(updated['sources'][0]['enabled'])
            self.assertEqual(module.prepare(self.event, self.issue, root), 'unchanged')

    def test_newer_or_closed_issue_skips_config_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder);path = root/'sources.json';original = json.dumps(self.config);path.write_text(original, encoding='utf-8')
            self.assertEqual(module.prepare(self.event, {**self.issue, 'body': 'updated'}, root), 'skip')
            self.assertEqual(module.prepare(self.event, {**self.issue, 'state': 'closed'}, root), 'skip')
            self.assertEqual(path.read_text(encoding='utf-8'), original)

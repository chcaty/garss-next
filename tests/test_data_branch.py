import subprocess
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
import sys
import json
from hashlib import sha256

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from publish_data import publish
from garss.snapshot import create_snapshot


class DataBranchTests(unittest.TestCase):
    def test_rolling_history_stays_one_commit_and_stale_writer_is_rejected(self):
        def git(*args, cwd):
            return subprocess.check_output(['git', *args], cwd=cwd, text=True, stderr=subprocess.DEVNULL).strip()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            remote = root / 'remote.git'
            git('init', '--bare', str(remote), cwd=root)
            config = {'sources':[]}
            first, second, stale = root / 'first', root / 'second', root / 'stale'
            for folder in (first, second, stale):
                create_snapshot(folder, [], config, datetime.now(timezone.utc))
            publish(first, str(remote), '')
            old = git('rev-parse', 'refs/heads/rss-data', cwd=remote)
            meta = json.loads((first / 'api/v1/meta.json').read_text(encoding='utf-8'))
            path = f"api/v1/snapshots/{meta['snapshot_id']}/articles.json"
            stored = subprocess.check_output(['git', 'show', f'rss-data:{path}'], cwd=remote)
            manifest = json.loads((first / 'api/v1/snapshots' / meta['snapshot_id'] / 'manifest.json').read_text(encoding='utf-8'))
            self.assertEqual(manifest['files']['articles.json'], {'bytes':len(stored), 'sha256':sha256(stored).hexdigest()})
            publish(second, str(remote), old)
            self.assertEqual(git('rev-list', '--count', 'rss-data', cwd=remote), '1')
            with self.assertRaises(subprocess.CalledProcessError):
                publish(stale, str(remote), old)
            self.assertEqual(git('rev-list', '--count', 'rss-data', cwd=remote), '1')

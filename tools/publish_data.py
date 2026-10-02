"""Replace only the rolling data branch, using compare-and-swap publication."""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'collector'))
from garss.snapshot import validate_snapshot


def run(*args, cwd):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def publish(folder: Path, remote: str, expected: str):
    meta = validate_snapshot(folder)
    if (folder / '.git').exists():
        raise ValueError('Publisher requires a fresh non-repository output folder')
    run('init', '--initial-branch=rss-data', cwd=folder)
    run('config', 'user.name', 'garss-data-bot', cwd=folder)
    run('config', 'user.email', 'garss-data-bot@users.noreply.github.com', cwd=folder)
    run('add', 'api', cwd=folder)
    run('commit', '-m', f"Snapshot {meta['snapshot_id']}", cwd=folder)
    run('remote', 'add', 'origin', remote, cwd=folder)
    # Never force main. Empty expected means the data branch must not yet exist.
    run('push', f'--force-with-lease=refs/heads/rss-data:{expected}',
        'origin', 'HEAD:refs/heads/rss-data', cwd=folder)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--remote', required=True)
    parser.add_argument('--expected', default='')
    args = parser.parse_args()
    publish(args.data, args.remote, args.expected)

"""Build a deployment tree from pinned source and validated data."""
import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'collector'))
from garss.snapshot import validate_snapshot


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    validate_snapshot(args.data)
    if args.output.exists():
        raise ValueError('Output must be a new directory')
    shutil.copytree(ROOT / 'web/public', args.output)
    shutil.copytree(ROOT / 'web/build', args.output / 'assets', dirs_exist_ok=True)
    shutil.copytree(args.data / 'api', args.output / 'api')
    (args.output / '.nojekyll').touch()


if __name__ == '__main__':
    main()

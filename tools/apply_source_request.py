"""Prepare the current owner's Issue request for validation and a normal Git push."""
import argparse
import json
import os
import sys
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'collector'))
from garss.source_request import parse_request, apply_request
from garss.catalog import load_sources


def prepare(event, current_issue, root):
    if current_issue.get('state') != 'open' or current_issue.get('body') != event['issue'].get('body'):
        return 'skip'
    if current_issue['user']['login'] != event['issue']['user']['login']:
        raise ValueError('Issue owner changed')
    request = parse_request(event)
    path = root / 'sources.json'
    config = load_sources(path)
    next_config = apply_request(config, request)
    if next_config == config:
        return 'unchanged'
    (root / 'build').mkdir(exist_ok=True)
    (root / 'build/base-sources.json').write_text(json.dumps(config, ensure_ascii=False), encoding='utf-8')
    path.write_text(json.dumps(next_config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    load_sources(path)
    return 'changed'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--event', type=Path, required=True)
    args = parser.parse_args()
    event = json.loads(args.event.read_text(encoding='utf-8'))
    # Validate authorization before reading any externally controlled content.
    parse_request(event)
    repository = event['repository']['full_name']
    response = requests.get(f'https://api.github.com/repos/{repository}/issues/{event["issue"]["number"]}',
                            headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                                     'Accept': 'application/vnd.github+json'}, timeout=30)
    response.raise_for_status()
    outcome = prepare(event, response.json(), ROOT)
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'outcome={outcome}\n')
    print(outcome)

"""Apply small owner-confirmed source patches without overwriting unrelated edits."""
import copy
import hashlib
import json
import re

MARKER = '<!-- shiyue-source-request:v1 -->'
FIELDS = {'title', 'description', 'category', 'feed_url', 'enabled', 'allow_undated',
          'recheck_requested_at', 'discovered_from', 'verified_at'}


def source_hash(source):
    return hashlib.sha256(json.dumps(source, sort_keys=True, ensure_ascii=False,
                                    separators=(',', ':')).encode('utf-8')).hexdigest()


def parse_request(event):
    issue, repository = event['issue'], event['repository']
    owner = repository['owner']['login'].casefold()
    if (issue.get('pull_request') or issue['user']['login'].casefold() != owner
            or event['sender']['login'].casefold() != owner):
        raise ValueError('Only the repository owner can confirm a source request')
    body = issue.get('body') or ''
    if len(body) > 100_000 or not body.strip().startswith(MARKER):
        raise ValueError('Invalid source request marker or size')
    blocks = re.findall(r'```json\s*\n(.*?)\n```', body, re.S)
    if len(blocks) != 1:
        raise ValueError('Expected one JSON source request')
    request = json.loads(blocks[0])
    if (type(request.get('version')) is not int or request['version'] != 1
            or request.get('repository') != repository['full_name']):
        raise ValueError('Source request targets a different repository or version')
    operations = request.get('operations')
    if not isinstance(operations, list) or not 1 <= len(operations) <= 40:
        raise ValueError('Source request must contain 1 to 40 operations')
    return request


def apply_request(config, request):
    result = copy.deepcopy(config)
    by_id = {source['id']: source for source in result['sources']}
    touched = set()
    for operation in request['operations']:
        if not isinstance(operation, dict) or set(operation) - {'id', 'before', 'set', 'remove'}:
            raise ValueError('Unsupported source operation')
        identity = operation.get('id')
        if not isinstance(identity, str) or not re.fullmatch(r'[A-Za-z0-9_-]+', identity) or identity in touched:
            raise ValueError('Invalid or repeated source ID')
        touched.add(identity)
        before, fields = operation.get('before'), operation.get('set')
        remove = operation.get('remove', False)
        if before is not None and (not isinstance(before, str) or not re.fullmatch(r'[a-f0-9]{64}', before)):
            raise ValueError('Invalid source version')
        if remove is not False and remove is not True:
            raise ValueError('Invalid deletion flag')
        if remove:
            if before is None or fields is not None:
                raise ValueError('Deletion requires a source version')
        elif not isinstance(fields, dict) or not fields or set(fields) - FIELDS:
            raise ValueError('Source fields are invalid')
        current = by_id.get(identity)
        if current is None and remove:
            continue  # A repeated successful deletion is harmless.
        if current is not None and not remove and all(current.get(key) == value for key, value in fields.items()):
            continue  # Retry a confirmed request without another commit.
        if (before is None and current is not None) or (before is not None and (current is None or source_hash(current) != before)):
            raise ValueError(f'Source {identity} has changed; reload published config and review your draft')
        if remove:
            result['sources'] = [source for source in result['sources'] if source['id'] != identity]
            by_id.pop(identity)
        elif current is None:
            source = {'id': identity, **fields}
            result['sources'].append(source)
            by_id[identity] = source
        else:
            current.update(fields)
    return result

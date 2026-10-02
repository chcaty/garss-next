"""Persist health across bounded data snapshots; transient outages never delete sources."""
from copy import deepcopy
from datetime import datetime, timedelta

ARCHIVE_FAILURES = 3
ARCHIVE_AFTER = timedelta(hours=24)
RETRY_AFTER = timedelta(days=7)

def stamp(now):
    return now.isoformat().replace('+00:00', 'Z')

def date(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00'))

def prepare(config, previous, now):
    states, due = {}, []
    for source in config['sources']:
        old = deepcopy(previous.get(source['id'], {}))
        signature = [source['feed_url'], source.get('recheck_requested_at', '')]
        if old.get('signature') != signature:
            old = {'signature': signature, 'failures': 0, 'status': 'pending'}
        states[source['id']] = old
        if source.get('enabled', True) and (old['status'] != 'archived' or not old.get('last_checked_at') or now - date(old['last_checked_at']) >= RETRY_AFTER):
            due.append(source)
    return states, due

def update(states, results, now):
    # A broad outage is evidence about the run, not evidence that every feed died.
    normal = [result for result in results if states[result.source.id]['status'] != 'archived']
    outage = bool(normal) and sum(bool(result.error) for result in normal) / len(normal) >= .8
    for result in results:
        state = states[result.source.id]
        state['last_checked_at'] = stamp(now)
        state['last_error'] = (result.error or '')[:500]
        if not result.error:
            state.update(status='active', failures=0, last_success_at=stamp(now))
            state.pop('first_failed_at', None)
            state.pop('archived_at', None)
        elif not outage or state['status'] == 'archived':
            state['failures'] += 1
            state.setdefault('first_failed_at', stamp(now))
            if state['failures'] >= ARCHIVE_FAILURES and now - date(state['first_failed_at']) >= ARCHIVE_AFTER:
                state.setdefault('archived_at', stamp(now))
                state['status'] = 'archived'
            elif state['status'] != 'archived':
                state['status'] = 'error'
    return outage

def effective_config(config, states):
    effective = deepcopy(config)
    for source in effective['sources']:
        if states[source['id']]['status'] == 'archived':
            source['enabled'] = False
    return effective

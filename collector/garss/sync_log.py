"""Bounded records of collection batches that reached publication."""
from .source_lifecycle import stamp


def publication_log(previous, results, states, started_at, finished_at, article_count, code_revision, workflow_run_id):
    run = {'generated_at': stamp(started_at), 'finished_at': stamp(finished_at),
           'duration_seconds': round((finished_at - started_at).total_seconds()),
           'checked': len(results), 'succeeded': sum(not item.error for item in results),
           'failed': sum(bool(item.error) for item in results),
           'archived': sum(state['status'] == 'archived' for state in states.values()),
           'article_count': article_count, 'workflow_run_id': workflow_run_id, 'code_revision': code_revision}
    return {'generated_at': stamp(started_at), 'runs': [run, *previous.get('runs', [])][:30]}

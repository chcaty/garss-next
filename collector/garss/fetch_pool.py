"""Bounded, connection-reusing feed collection with duplicate URL coalescing."""
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import replace

import requests

from .fetch import fetch_feed
from .models import FeedResult

LOGGER = logging.getLogger(__name__)


def fetch_all(sources, fetch_date, workers: int, cache=None, bootstrap_ids=(), retention_days=30) -> list[FeedResult]:
    if workers < 1:
        raise ValueError("workers must be at least 1")
    if not sources:
        return []
    local = threading.local()
    sessions = []
    session_lock = threading.Lock()
    bootstrap_urls = {source.feed_url for source in sources if source.id in bootstrap_ids}

    def fetch_one(source):
        if not hasattr(local, "session"):
            local.session = requests.Session()
            with session_lock:
                sessions.append(local.session)
        # Reuse connections, not cookies received from unrelated feeds.
        local.session.cookies.clear()
        return fetch_feed(source, today=fetch_date, only_date=None if source.feed_url in bootstrap_urls else fetch_date,
                          retention_days=retention_days,
                          request_get=local.session.get, cache=cache)

    try:
        return _collect_feeds(sources, workers, fetch_one)
    finally:
        for session in sessions:
            session.close()


def _collect_feeds(sources, workers, fetch_one):
    sources_by_url = {}
    for source in sources:
        sources_by_url.setdefault(source.feed_url, []).append(source)
    results_by_id = {}
    with ThreadPoolExecutor(max_workers=min(workers, len(sources_by_url))) as executor:
        futures = {
            executor.submit(fetch_one, group[0]): group
            for group in sources_by_url.values()
        }
        completed = 0
        for future in as_completed(futures):
            group = futures[future]
            source = group[0]
            try:
                result = future.result()
            except (
                Exception
            ) as error:  # Keep one broken source from aborting all feeds.
                LOGGER.exception("Unexpected fetch failure for %s", source.id)
                result = FeedResult(source=source, error=str(error))
            for member in group:
                # One download, but distinct article IDs and independent lists.
                results_by_id[member.id] = FeedResult(
                    source=member,
                    articles=[replace(article, source_id=member.id) for article in result.articles],
                    error=result.error,
                )
            completed += len(group)
            LOGGER.info("Progress: %d/%d", completed, len(sources))
    return [results_by_id[source.id] for source in sources]



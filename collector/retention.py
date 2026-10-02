"""Retention helpers for generated RSS article information."""

from collections.abc import Iterable, Mapping
from datetime import date, datetime, timedelta, timezone

DEFAULT_RETENTION_DAYS = 30


def retention_cutoff(
    today: date | None = None,
    retention_days: int = DEFAULT_RETENTION_DAYS,
) -> date:
    """Return the oldest date that should still be retained (inclusive)."""
    if retention_days < 1:
        raise ValueError("retention_days must be at least 1")
    if today is None:
        today = datetime.now(timezone.utc).date()
    # Include today: a 30-day window spans today and the preceding 29 dates.
    return today - timedelta(days=retention_days - 1)


def entry_published_datetime(entry: Mapping) -> datetime | None:
    """Read a feedparser entry timestamp as an aware UTC datetime."""
    published = entry.get("published_parsed") or entry.get("updated_parsed")
    if not published or len(published) < 6:
        return None
    try:
        return datetime(*map(int, published[:6]), tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


def entry_published_date(entry: Mapping) -> date | None:
    """Read a feedparser entry date without raising on incomplete feeds."""
    published_at = entry_published_datetime(entry)
    return published_at.date() if published_at else None


def filter_recent_entries(
    entries: Iterable[Mapping],
    today: date | None = None,
    retention_days: int = DEFAULT_RETENTION_DAYS,
):
    """Keep entries published during the configured retention window."""
    cutoff = retention_cutoff(today=today, retention_days=retention_days)
    return [
        entry
        for entry in entries
        if (entry_date := entry_published_date(entry)) is not None
        and entry_date >= cutoff
    ]

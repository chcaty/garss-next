import json
import logging
from datetime import datetime
from dataclasses import replace
from pathlib import Path

from garss.catalog import safe_http_url
from garss.models import Article, FeedResult
from garss.article_retention import MIN_ARTICLES_PER_SOURCE, retain_articles
from garss.article_identity import article_key

LOGGER = logging.getLogger(__name__)


def load_cached_articles(path: Path, source_ids: set[str]) -> list[Article]:
    """Load previously generated articles, ignoring malformed cache entries."""
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        LOGGER.warning("Article cache ignored: %s", error)
        return []

    articles = []
    if not isinstance(payload, dict) or not isinstance(payload.get("articles"), list):
        LOGGER.warning("Article cache ignored: invalid document structure")
        return articles
    for item in payload.get("articles", []):
        try:
            source_id = str(item["source_id"])
            if source_id not in source_ids:
                continue
            published_at = datetime.fromisoformat(
                str(item["published_at"]).replace("Z", "+00:00")
            )
            if published_at.tzinfo is None:
                continue
            articles.append(
                Article(
                    source_id=source_id,
                    title=str(item["title"]),
                    url=safe_http_url(str(item["url"])),
                    published_at=published_at,
                    summary=str(item.get("summary", ""))[:600],
                    image_url=_cached_image(item.get("image_url")),
                )
            )
        except (KeyError, TypeError, ValueError):
            continue
    return articles


def _cached_image(value):
    try:
        return safe_http_url(str(value)) if value else ""
    except ValueError:
        return ""


def enrich_cached_articles(articles, sources, response_cache, today, retention_days):
    """Backfill only existing article IDs from cached RSS, without new requests."""
    from garss.fetch import _parse_articles
    media_by_source = {}
    parsed_by_url = {}
    for source in sources:
        if source.feed_url not in parsed_by_url:
            cached = response_cache.get(source.feed_url)
            try:
                parsed_by_url[source.feed_url] = {article.url: article for article in _parse_articles(source, cached.payload, today=today, retention_days=retention_days)} if cached else {}
            except (ValueError, TypeError):
                parsed_by_url[source.feed_url] = {}
        media_by_source[source.id] = parsed_by_url[source.feed_url]
    result = []
    for article in articles:
        metadata = media_by_source.get(article.source_id, {}).get(article.url)
        result.append(replace(article, summary=article.summary or metadata.summary, image_url=article.image_url or metadata.image_url) if metadata else article)
    return result


def merge_recent_history(
    results: list[FeedResult],
    cached_articles: list[Article],
    today,
    retention_days: int,
    minimum_articles: int = MIN_ARTICLES_PER_SOURCE,
) -> list[FeedResult]:
    """Merge the feed and cache, keeping the window plus each source's latest posts."""
    articles_by_source = {result.source.id: {} for result in results}
    for article in cached_articles:
        if article.source_id in articles_by_source:
            articles_by_source[article.source_id].setdefault(article_key(article.url), article)

    for result in results:
        merged = articles_by_source[result.source.id]
        for article in result.articles:
            key = article_key(article.url)
            previous = merged.get(key)
            # Keep historical URLs/IDs so existing bookmarks and read records survive.
            candidate = replace(article, url=previous.url,
                                summary=article.summary or previous.summary,
                                image_url=article.image_url or previous.image_url) if previous else article
            merged[key] = article if candidate == article else candidate

    for result in results:
        result.articles = retain_articles(
            articles_by_source[result.source.id].values(),
            today, retention_days, minimum_articles,
        )
    return results

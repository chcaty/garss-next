"""Keep the rolling window plus a small archive for quiet publishers."""
from garss.timezones import app_date
from retention import retention_cutoff

MIN_ARTICLES_PER_SOURCE = 5


def retain_articles(articles, today, retention_days, minimum=MIN_ARTICLES_PER_SOURCE, only_date=None):
    if minimum < 0:
        raise ValueError("minimum article count must not be negative")
    cutoff = retention_cutoff(today=today, retention_days=retention_days)
    ordered = sorted(
        (article for article in articles if app_date(article.published_at) <= today),
        key=lambda article: article.published_at,
        reverse=True,
    )
    return [
        article for index, article in enumerate(ordered)
        if index < minimum or (
            app_date(article.published_at) == only_date if only_date is not None
            else app_date(article.published_at) >= cutoff
        )
    ]

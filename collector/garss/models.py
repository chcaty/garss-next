from dataclasses import dataclass, field
from datetime import datetime
from hashlib import sha256


@dataclass(frozen=True)
class FeedSource:
    id: str
    title: str
    description: str
    feed_url: str
    allow_undated: bool = False

    def as_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "feed_url": self.feed_url,
        }


@dataclass(frozen=True)
class SourceTemplate:
    source: FeedSource
    row: str
    display_id: str = ""
    category: str = ""
    icon: str = ""


@dataclass(frozen=True)
class Article:
    source_id: str
    title: str
    url: str
    published_at: datetime
    summary: str = ""
    image_url: str = ""
    date_inferred: bool = False

    @property
    def id(self):
        value = f"{self.source_id}\0{self.url}".encode()
        return sha256(value).hexdigest()[:20]

    def as_dict(self):
        return {
            "id": self.id,
            "source_id": self.source_id,
            "title": self.title,
            "url": self.url,
            "published_at": self.published_at.isoformat().replace("+00:00", "Z"),
            "summary": self.summary,
            "image_url": self.image_url,
            "date_inferred": self.date_inferred,
        }


@dataclass
class FeedResult:
    source: FeedSource
    articles: list[Article] = field(default_factory=list)
    error: str | None = None
    # Optional observations keep old producers and v1 consumers compatible.
    raw_entry_count: int | None = None
    valid_article_count: int | None = None
    new_article_count: int | None = None
    drop_reasons: dict[str, int] | None = None
    last_new_article_at: datetime | None = None
    http_status: int | None = None

    def health(self):
        values = {name: getattr(self, name) for name in (
            'raw_entry_count', 'valid_article_count', 'new_article_count', 'drop_reasons',
        ) if getattr(self, name) is not None}
        if self.last_new_article_at is not None:
            values['last_new_article_at'] = self.last_new_article_at.isoformat().replace('+00:00', 'Z')
        return values

    @property
    def status(self):
        return "error" if self.error else "ok"

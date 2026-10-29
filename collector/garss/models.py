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
    adapter: str = 'rss'

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
    content_type: str = 'article'
    metadata: dict = field(default_factory=dict)

    @property
    def id(self):
        value = f"{self.source_id}\0{self.url}".encode()
        return sha256(value).hexdigest()[:20]

    def as_dict(self):
        value = {
            "id": self.id,
            "source_id": self.source_id,
            "title": self.title,
            "url": self.url,
            "published_at": self.published_at.isoformat().replace("+00:00", "Z"),
            "summary": self.summary,
            "image_url": self.image_url,
            "date_inferred": self.date_inferred,
        }
        if self.content_type != 'article' or self.metadata:
            value.update(content_type=self.content_type, metadata=self.metadata)
        return value


@dataclass
class FeedResult:
    source: FeedSource
    articles: list[Article] = field(default_factory=list)
    error: str | None = None

    @property
    def status(self):
        return "error" if self.error else "ok"

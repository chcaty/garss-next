"""Extract readable plain text; never expose publisher HTML as executable UI."""
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit


class _TextParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0
        self.images = []

    def handle_starttag(self, tag, attrs):
        if tag == "img":
            attributes = dict(attrs)
            self.images.append(attributes.get("src") or attributes.get("data-src") or "")
        if tag in {"script", "style"}:
            self.hidden += 1
        if tag in {"p", "br", "div", "li"} and not self.hidden:
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if tag in {"script", "style"}:
            self.hidden = max(0, self.hidden - 1)
        if tag in {"p", "div", "li"} and not self.hidden:
            self.parts.append(" ")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def plain_summary(value, limit=600):
    parser = _TextParser()
    parser.feed(str(value or "")[:30000])
    return " ".join("".join(parser.parts).split())[:limit]


def entry_image(entry, base_url):
    candidates = [item.get("url", "") for key in ("media_thumbnail", "media_content") for item in entry.get(key, []) if isinstance(item, dict)]
    candidates += [item.get("href", "") for item in entry.get("enclosures", []) if str(item.get("type", "")).startswith("image/")]
    parser = _TextParser()
    for content in entry.get("content", []):
        parser.feed(str(content.get("value", ""))[:30000])
    parser.feed(str(entry.get("summary", ""))[:30000])
    for value in candidates + parser.images:
        if not value:
            continue
        try:
            url = urljoin(base_url, str(value).strip())
            parsed = urlsplit(url)
        except ValueError:
            continue
        if parsed.scheme in {"https", "http"} and parsed.hostname and not parsed.username and not parsed.password and len(url) <= 2048 and not any(ord(char) < 32 for char in url):
            return url
    return ""

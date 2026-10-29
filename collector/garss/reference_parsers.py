"""Parsing functions reused from the user-provided web-monitor (2026-10-29).

Original transport is replaced by a per-call injected reader. This module never
opens network connections, writes data, schedules jobs, or executes page scripts.
"""
import json
import re
from datetime import datetime
from email.utils import parsedate_to_datetime
from urllib.parse import quote as urlquote

JAVDB_URL = "https://javdb.com/rankings/movies?p=daily&t=censored"

def clean(text: str) -> str:
    """去标签、解实体、压空白。"""
    text = re.sub(r"<script\b.*?</script>", " ", text, flags=re.S | re.I)
    text = re.sub(r"<style\b.*?</style>", " ", text, flags=re.S | re.I)
    text = re.sub(r"<[^>]+>", "", text)
    ents = {
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"',
        "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#x27;": "'",
    }
    for k, v in ents.items():
        text = text.replace(k, v)
    text = re.sub(r"&#(\d+);", lambda m: chr(int(m.group(1))), text)
    return re.sub(r"\s+", " ", text).strip()


def to_int(text: str) -> int:
    digits = re.sub(r"[^\d]", "", text or "")
    return int(digits) if digits else 0


def collect_github_trending(fetch) -> list[dict]:
    html = fetch("https://github.com/trending?since=daily")
    chunks = html.split('<article class="Box-row"')[1:]
    rows: list[dict] = []

    for ci, chunk in enumerate(chunks):
        block = chunk.split("</article>")[0]

        m = re.search(r'<h2[^>]*>.*?href="/([^"/]+/[^"/]+)"', block, re.S)
        if not m:
            continue
        repo = m.group(1).strip()
        url = f"https://github.com/{repo}"
        owner = repo.split("/")[0]

        d = re.search(r'<p[^>]*class="[^"]*col-9[^"]*"[^>]*>(.*?)</p>', block, re.S)
        desc = clean(d.group(1)) if d else ""

        lang = re.search(r'itemprop="programmingLanguage">([^<]+)<', block)
        language = clean(lang.group(1)) if lang else ""

        total = re.search(r'/stargazers"[^>]*>(.*?)</a>', block, re.S)
        stars = to_int(clean(total.group(1))) if total else 0

        forks = re.search(r'/forks"[^>]*>(.*?)</a>', block, re.S)
        forks_n = to_int(clean(forks.group(1))) if forks else 0

        today_m = re.search(r'([\d,]+)\s+stars\s+today', block)
        stars_today = to_int(today_m.group(1)) if today_m else 0

        rows.append({
            "key": repo.lower(),
            "rank": ci + 1,
            "repo": repo,
            "owner": owner,
            "avatar": f"https://github.com/{owner}.png?size=64",
            "url": url,
            "language": language,
            "stars": stars,
            "stars_today": stars_today,
            "forks": forks_n,
            "description": desc[:300],
        })

    rows.sort(key=lambda r: r["stars_today"], reverse=True)
    for i, r in enumerate(rows, 1):
        r["rank"] = i
    return rows


def collect_javdb(fetch) -> list[dict]:
    html = fetch(JAVDB_URL)
    chunks = html.split('<div class="item">')[1:]
    rows: list[dict] = []
    seen: set[str] = set()

    for chunk in chunks:
        block = chunk.split('<div class="item">')[0]
        link = re.search(r'href="(/v/[A-Za-z0-9]+)"\s+class="box"', block)
        if not link:
            continue
        path = link.group(1)

        code_m = re.search(r'<div class="video-title">\s*<strong>([^<]*)</strong>(.*?)</div>', block, re.S)
        if code_m:
            code = clean(code_m.group(1))
            title = clean(code_m.group(2))
        else:
            code, title = "", ""

        key = (code or path).strip()
        if not title and not code or key.lower() in seen:
            continue
        seen.add(key.lower())

        score_m = re.search(r"([\d.]+)\s*分,\s*由\s*(\d+)\s*人評價", block)
        rating = float(score_m.group(1)) if score_m else 0.0
        votes = int(score_m.group(2)) if score_m else 0

        date_m = re.search(r'<div class="meta">\s*([\d-]{8,10})\s*</div>', block)
        released = date_m.group(1) if date_m else ""

        tags = [clean(t) for t in re.findall(r'<span class="tag[^"]*"[^>]*>([^<]+)</span>', block)]
        has_magnet = any("磁" in t for t in tags)

        cover_m = re.search(r'<div class="cover[^"]*">(.*?)</div>', block, re.S)
        cover_html = cover_m.group(1) if cover_m else ""
        img_m = re.search(r'<img[^>]*?src="([^"]+)"', cover_html)
        cover = img_m.group(1) if img_m else ""
        playable = "可播放" in cover_html

        rows.append({
            "key": key,
            "rank": len(rows) + 1,          # 页面顺序即榜单名次
            "code": code,
            "title": title[:200],
            "url": f"https://javdb.com{path}",
            "cover": cover,
            "playable": "可播放" if playable else "",
            "rating": rating,
            "votes": votes,
            "released": released,
            "magnet": "是" if has_magnet else "",
            "tags": "|".join(tags[:6]),
        })

    return rows


def collect_gossip(fetch) -> list[dict]:
    html = fetch("https://access.xgmxzbij.cc/")
    chunks = re.split(r"<article\b", html)[1:]
    rows: list[dict] = []
    seen: set[str] = set()

    for chunk in chunks:
        block = chunk.split("</article>")[0]

        u = re.search(r'itemprop="url mainEntityOfPage"\s+content="([^"]+)"', block)
        if not u:
            continue
        path = u.group(1).strip()
        if path in seen:
            continue
        seen.add(path)

        t = re.search(r"<h2[^>]*>(.*?)</h2>", block, re.S)
        if not t:
            continue
        title = clean(t.group(1))
        if not title:
            continue

        d = re.search(r'itemprop="datePublished"\s+content="([^"]+)"', block)
        published = d.group(1)[:19].replace("T", " ") if d else ""

        badge = re.search(r'<span class="post-card-title">(.*?)</span>\s*</div>', block, re.S)
        category = clean(badge.group(1)) if badge else ""

        cover = re.search(r'itemprop="image"\s+content="([^"]+)"', block)

        rows.append({
            "key": path,
            "title": title[:200],
            "category": category[:40],
            "published": published,
            "url": path if path.startswith("http") else f"https://access.xgmxzbij.cc{path}",
            "cover": cover.group(1) if cover else "",
        })

    return rows


def _heat_text(num: int) -> str:
    if num >= 100_000_000:
        return f"{num / 100_000_000:.1f}亿"
    if num >= 10_000:
        return f"{num / 10_000:.1f}万"
    return str(num)


def collect_weibo_hot(fetch) -> list[dict]:
    txt = fetch(
        "https://weibo.com/ajax/side/hotSearch",
        headers={"Referer": "https://weibo.com/", "Accept": "application/json"},
    )
    payload = json.loads(txt)
    data = payload.get("data") or {}
    realtime = data.get("realtime") or []
    rows: list[dict] = []

    # 置顶（通常是官方重大事件），单独一条放最前
    for gv in (data.get("hotgovs") or [])[:1]:
        word = clean(gv.get("name") or gv.get("word") or "").strip("#")
        if word:
            rows.append({
                "key": ("置顶:" + word).lower(),
                "rank": 0,
                "keyword": word,
                "label": "置顶",
                "heat": "",
                "heat_num": 0,
                "topic": "",
                "url": f"https://s.weibo.com/weibo?q={urlquote(word)}",
            })

    for item in realtime:
        word = clean(item.get("word") or "")
        if not word:
            continue
        num = int(item.get("num") or 0)
        label = clean(item.get("label_name") or item.get("icon_desc") or "")
        scheme = item.get("word_scheme") or word
        rows.append({
            "key": word.lower(),
            "rank": len(rows) + 1,
            "keyword": word,
            "label": label,
            "heat": _heat_text(num),
            "heat_num": num,
            "topic": "话题" if item.get("topic_flag") else "",
            "url": f"https://s.weibo.com/weibo?q={urlquote(scheme)}",
        })

    return rows


def collect_toutiao(fetch) -> list[dict]:
    txt = fetch(
        "https://www.toutiao.com/hot-event/hot-board/?origin=toutiao_pc",
        headers={"Accept": "application/json"},
    )
    data = (json.loads(txt) or {}).get("data") or []
    rows: list[dict] = []
    seen: set[str] = set()

    for it in data:
        title = clean(it.get("Title") or "")
        key = str(it.get("ClusterIdStr") or it.get("ClusterId") or title)
        if not title or key in seen:
            continue
        seen.add(key)

        img = it.get("Image")
        if isinstance(img, dict):
            cover = img.get("url") or ""
        elif isinstance(img, str):
            cover = img
        else:
            cover = ""

        rows.append({
            "key": key,
            "rank": len(rows) + 1,
            "title": title[:120],
            "hot": _heat_text(to_int(it.get("HotValue") or "0")),
            "hot_num": to_int(it.get("HotValue") or "0"),
            "label": clean(it.get("LabelDesc") or ""),
            "cover": cover,
            "url": it.get("Url") or f"https://www.toutiao.com/trending/{key}/",
        })

    return rows


def _dur(sec) -> str:
    try:
        sec = int(sec)
    except Exception:
        return ""
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def collect_bilibili(fetch) -> list[dict]:
    txt = fetch("https://api.bilibili.com/x/web-interface/ranking/v2?rid=0&type=all",
                headers={"Accept": "application/json"})
    payload = json.loads(txt)
    items = ((payload or {}).get("data") or {}).get("list") or []
    rows: list[dict] = []

    for it in items[:50]:                    # 热门榜默认 100 条，取前 50 控体积
        bvid = it.get("bvid") or ""
        title = clean(it.get("title") or "")
        if not bvid or not title:
            continue
        stat = it.get("stat") or {}
        pic = it.get("pic") or ""
        if pic.startswith("http://"):
            pic = "https://" + pic[7:]
        rows.append({
            "key": bvid,
            "rank": len(rows) + 1,
            "title": title[:120],
            "cover": pic,
            "owner": clean((it.get("owner") or {}).get("name") or ""),
            "category": clean(it.get("tname") or ""),
            "views": stat.get("view") or 0,
            "likes": stat.get("like") or 0,
            "replies": stat.get("reply") or 0,
            "duration": _dur(it.get("duration") or 0),
            "pubdate": it.get("pubdate") or 0,
            "url": f"https://www.bilibili.com/video/{bvid}",
        })

    return rows


def collect_v2ex(fetch) -> list[dict]:
    txt = fetch("https://www.v2ex.com/api/topics/hot.json")
    items = json.loads(txt) or []
    rows: list[dict] = []

    for it in items:
        title = clean(it.get("title") or "")
        if not title:
            continue
        rows.append({
            "key": str(it.get("id") or title),
            "rank": len(rows) + 1,
            "title": title[:120],
            "node": clean((it.get("node") or {}).get("title") or ""),
            "author": clean((it.get("member") or {}).get("username") or ""),
            "replies": it.get("replies") or 0,
            "created": it.get("created") or 0,
            "url": it.get("url") or "",
        })

    return rows


def collect_sspai(fetch) -> list[dict]:
    txt = fetch("https://sspai.com/api/v1/article/index/page/get?limit=20&offset=0")
    items = (json.loads(txt) or {}).get("data") or []
    rows: list[dict] = []

    for it in items:
        title = clean(it.get("title") or "")
        if not title:
            continue
        banner = it.get("banner") or ""
        if banner and not banner.startswith("http"):
            banner = "https://cdn.sspai.com/" + banner.lstrip("/")
        rows.append({
            "key": str(it.get("id") or title),
            "rank": len(rows) + 1,
            "title": title[:120],
            "summary": clean(it.get("summary") or "")[:160],
            "cover": banner,
            "likes": it.get("like_count") or 0,
            "comments": it.get("comment_count") or 0,
            "published": it.get("released_time") or 0,
            "url": f"https://sspai.com/post/{it.get('id')}",
        })

    return rows


def _clean(text: str, limit: int = 300) -> str:
    if not text:
        return ""
    text = re.sub(r"<script\b.*?</script>", " ", text, flags=re.S | re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    text = (text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
                .replace("&quot;", '"').replace("&#39;", "'").replace("&nbsp;", " ")
                .replace("&apos;", "'").replace("&mdash;", "—"))
    text = re.sub(r"&#(\d+);", lambda m: chr(int(m.group(1))), text)
    return re.sub(r"\s+", " ", text).strip()[:limit]


def _fmt_time(dt) -> str:
    try:
        return dt.strftime("%m-%d %H:%M")
    except Exception:
        return ""


def _feed_time(raw: str) -> str:
    raw = (raw or "").strip()
    if not raw:
        return ""
    try:
        return _fmt_time(parsedate_to_datetime(raw))
    except Exception:
        pass
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d %H:%M:%S"):
        try:
            return _fmt_time(datetime.strptime(raw.replace("Z", "+0000"), fmt))
        except Exception:
            continue
    return raw[:16]


def _num(n) -> str:
    try:
        n = int(n)
    except Exception:
        return ""
    if n >= 100_000_000:
        return f"{n / 100_000_000:.1f}亿"
    if n >= 10_000:
        return f"{n / 10_000:.1f}万"
    return str(n)


def collect_bili_hotword(_json) -> list[dict]:
    data = _json("https://s.search.bilibili.com/main/hotword")
    rows = []
    for it in (data.get("list") or [])[:30]:
        kw = _clean(it.get("keyword") or it.get("show_name") or "", 80)
        if not kw:
            continue
        rows.append({
            "key": kw, "rank": len(rows) + 1, "title": kw,
            "url": "https://search.bilibili.com/all?keyword=" + urlquote(kw),
            "cover": "", "desc": "", "author": "", "category": "热词",
            "extra": "", "heat_text": "", "heat_num": 0, "time_text": "",
        })
    return rows


def collect_zhihu_daily(_json) -> list[dict]:
    data = _json("https://news-at.zhihu.com/api/4/news/latest")
    rows = []
    for it in (data.get("stories") or [])[:15]:
        title = _clean(it.get("title") or "", 160)
        if not title:
            continue
        images = it.get("images") or []
        rows.append({
            "key": str(it.get("id")), "rank": len(rows) + 1, "title": title,
            "url": it.get("url") or f"https://daily.zhihu.com/story/{it.get('id')}",
            "cover": images[0] if images else "", "desc": _clean(it.get("hint") or "", 120),
            "author": "", "category": "", "extra": "", "heat_text": "", "heat_num": 0,
            "time_text": "",
        })
    return rows


def collect_douban_hot(_json) -> list[dict]:
    data = _json("https://movie.douban.com/j/search_subjects?type=movie&tag=%E7%83%AD%E9%97%A8"
                 "&sort=recommend&page_limit=20&page_start=0")
    rows = []
    for it in (data.get("subjects") or [])[:20]:
        title = _clean(it.get("title") or "", 120)
        if not title:
            continue
        rows.append({
            "key": str(it.get("id")), "rank": len(rows) + 1, "title": title,
            "url": it.get("url") or "",
            "cover": it.get("cover") or "", "desc": "",
            "author": "", "category": "热门",
            "extra": f"评分 {it.get('rate')}" if it.get("rate") else "",
            "heat_text": "", "heat_num": 0, "time_text": "",
        })
    return rows


def collect_douban_new(_json) -> list[dict]:
    data = _json("https://movie.douban.com/j/new_search_subjects?sort=U&range=0,10&tags=&start=0")
    rows = []
    for it in (data.get("data") or [])[:20]:
        title = _clean(it.get("title") or "", 120)
        if not title:
            continue
        directors = "、".join(it.get("directors") or [])
        rows.append({
            "key": str(it.get("id")), "rank": len(rows) + 1, "title": title,
            "url": it.get("url") or "",
            "cover": it.get("cover") or "",
            "desc": f"导演 {directors}" if directors else "",
            "author": directors, "category": "",
            "extra": f"评分 {it.get('rate')}" if it.get("rate") else "",
            "heat_text": "", "heat_num": 0, "time_text": "",
        })
    return rows


def collect_juejin(_json) -> list[dict]:
    data = _json("https://api.juejin.cn/content_api/v1/content/article_rank?category_id=1&type=hot")
    rows = []
    for it in (data.get("data") or [])[:25]:
        content = it.get("content") or {}
        counter = it.get("content_counter") or {}
        title = _clean(content.get("title") or "", 160)
        cid = content.get("content_id")
        if not title or not cid:
            continue
        rows.append({
            "key": str(cid), "rank": len(rows) + 1, "title": title,
            "url": f"https://juejin.cn/post/{cid}",
            "cover": "",
            "desc": _clean(content.get("brief") or "", 140),
            "author": (it.get("author") or {}).get("name") or "",
            "category": "",
            "extra": f"阅读 {_num(counter.get('view'))}|赞 {_num(counter.get('like'))}",
            "views": counter.get("view") or 0, "likes": counter.get("like") or 0,
            "heat_text": "", "heat_num": counter.get("view") or 0,
            "time_text": "",
        })
    return rows


def collect_hn(_json) -> list[dict]:
    ids = _json("https://hacker-news.firebaseio.com/v0/topstories.json") or []
    rows = []
    for sid in ids[:10]:
        try:
            it = _json(f"https://hacker-news.firebaseio.com/v0/item/{sid}.json")
        except Exception:
            continue
        title = _clean(it.get("title") or "", 160)
        if not title:
            continue
        url = it.get("url") or f"https://news.ycombinator.com/item?id={sid}"
        rows.append({
            "key": str(sid), "rank": len(rows) + 1, "title": title,
            "url": url, "cover": "", "desc": "",
            "author": it.get("by") or "", "category": "HN",
            "extra": f"▲{it.get('score') or 0}|💬{it.get('descendants') or 0}",
            "score": it.get("score") or 0, "replies": it.get("descendants") or 0,
            "heat_text": "", "heat_num": it.get("score") or 0,
            "time_text": _fmt_time(datetime.fromtimestamp(it.get("time") or 0)),
        })
    return rows


def collect_lobsters(_json) -> list[dict]:
    data = _json("https://lobste.rs/hottest.json")
    rows = []
    for it in (data or [])[:20]:
        title = _clean(it.get("title") or "", 160)
        if not title:
            continue
        tags = ", ".join(it.get("tags") or [])
        rows.append({
            "key": it.get("short_id") or title, "rank": len(rows) + 1, "title": title,
            "url": it.get("url") or f"https://lobste.rs/s/{it.get('short_id')}",
            "cover": "", "desc": _clean(it.get("description") or "", 140),
            "author": it.get("submitter_user") or "", "category": tags,
            "extra": f"▲{it.get('score') or 0}|💬{it.get('comment_count') or 0}",
            "score": it.get("score") or 0, "replies": it.get("comment_count") or 0,
            "heat_text": "", "heat_num": it.get("score") or 0,
            "time_text": _feed_time(it.get("created_at") or ""),
        })
    return rows


def collect_devto(_json) -> list[dict]:
    data = _json("https://dev.to/api/articles?top=1&per_page=20")
    rows = []
    for it in (data or [])[:20]:
        title = _clean(it.get("title") or "", 160)
        if not title:
            continue
        rows.append({
            "key": str(it.get("id")), "rank": len(rows) + 1, "title": title,
            "url": it.get("url") or "", "cover": it.get("cover_image") or "",
            "desc": _clean(it.get("description") or "", 140),
            "author": (it.get("user") or {}).get("name") or "",
            "category": ", ".join(it.get("tag_list") or []),
            "extra": f"♥{it.get('positive_reactions_count') or 0}|💬{it.get('comments_count') or 0}",
            "likes": it.get("positive_reactions_count") or 0, "replies": it.get("comments_count") or 0,
            "heat_text": "", "heat_num": it.get("positive_reactions_count") or 0,
            "time_text": _feed_time(it.get("published_at") or ""),
        })
    return rows


def collect_stackoverflow(_json) -> list[dict]:
    data = _json("https://api.stackexchange.com/2.3/questions?order=desc&sort=hot"
                 "&site=stackoverflow&pagesize=20&filter=default")
    rows = []
    for it in (data.get("items") or [])[:20]:
        title = _clean(it.get("title") or "", 160)
        if not title:
            continue
        rows.append({
            "key": str(it.get("question_id")), "rank": len(rows) + 1, "title": title,
            "url": it.get("link") or "", "cover": "", "desc": "",
            "author": (it.get("owner") or {}).get("display_name") or "",
            "category": ", ".join((it.get("tags") or [])[:3]),
            "extra": f"▲{it.get('score') or 0}|答 {it.get('answer_count') or 0}",
            "score": it.get("score") or 0, "answers": it.get("answer_count") or 0,
            "heat_text": "", "heat_num": it.get("score") or 0,
            "time_text": _fmt_time(datetime.fromtimestamp(it.get("creation_date") or 0)),
        })
    return rows


def collect_baidu_pc(_json) -> list[dict]:
    data = _json("https://top.baidu.com/api/board?platform=pc&tab=realtime")
    rows = []
    cards = ((data.get("data") or {}).get("cards") or [])
    items = (cards[0].get("content") if cards else []) or []      # pc 版是平铺列表
    for it in items:
        word = _clean(it.get("query") or it.get("word") or "", 120)
        if not word:
            continue
        hot = it.get("hotScore") or 0
        rows.append({
            "key": word, "rank": len(rows) + 1, "title": word,
            "url": it.get("appUrl") or it.get("url") or "https://www.baidu.com/s?wd=" + urlquote(word),
            "cover": it.get("img") or "",
            "desc": _clean(it.get("desc") or "", 120),
            "author": "", "category": "",
            "extra": "",
            "heat_text": _num(hot) if hot else "",
            "heat_num": int(hot) if str(hot).isdigit() else 0,
            "time_text": "",
        })
    return rows

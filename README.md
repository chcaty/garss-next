# GARSS Next

GitHub Actions 采集 RSS，GitHub Pages 展示文章与管理来源，Flutter 手机客户端读取经过校验的 JSON。新仓库不继承旧 Git 历史。

## 目录与语言

- `collector/`：Python RSS 解析、条件请求、并发采集、历史合并和去重。
- `web/`：TypeScript 阅读页；来源管理页采用 React + Headless UI + Tailwind CSS，单独打包，不影响手机 APK。
- `app/`：Flutter / Dart Android 客户端。
- `sources.json`：唯一的公共采集来源配置。`enabled: false` 会停止 CI 采集。
- `tools/`：校验、采集、静态构建、数据分支发布。

## 分支与发布

`main` 只保存源码、测试、依赖锁文件和来源配置。`rss-data` 是由 CI 管理的独立滚动快照分支：每次只有一个根提交，使用 `--force-with-lease` 校验旧版本后替换，绝不合并回 main。每次采集保留当前与前一份不可变 JSON 快照；备份 artifact 保留 14 天。分支替换限制可达历史，GitHub 对不可达对象的物理回收不由项目控制。

Pages 采用 GitHub Actions artifact 部署，不需要 gh-pages 分支。修改网页只构建发布，不采集；采集流程更新数据后调用发布流程。每天北京时间 06:00、13:00、17:00、22:00 触发，另外支持手动触发。失败时保留已发布数据；部署失败可以单独重试。

来源管理页支持编辑、新增、停用、删除、筛选、批量启停与 OPML 导入导出。草稿只存浏览器；复制或下载配置后，在 GitHub 编辑 `sources.json`，选择新分支并创建 PR，校验并合并后才生效。页面不保存 GitHub token。PR 实时校验新增或重新启用的 RSS 地址；网络不可用时会报告校验失败，不静默接受。

## 数据契约

保留 v1 manifest / SHA-256 校验接口。文章 ID 按保守规范化后的原文链接生成；普通锚点和明确追踪参数不影响身份，内容查询参数和 hash 路由保留。`source_ids` 保存多个来源归属，信息流只显示一篇；不按标题去重。摘要、图片缺失时沿用历史有效内容。近 30 天文章加每个启用来源至少最近 5 篇；文章发布时间晚于当前日期不纳入。

来源配置、采集状态、文章数据分开；手机的关注是本机筛选偏好，不改变公共采集配置。手机现阶段沿用迁入的阅读客户端，待读队列与新的阅读界面属于后续产品改造，不在本次仓库重建中伪装为已完成。

## 本地验证

```sh
python -m venv .venv
# 激活虚拟环境后：
pip install -r requirements.txt
PYTHONPATH=collector python -m unittest discover -s tests -q
python tools/validate_sources.py
npm ci
npm run check
npm test
npm run build
python tools/collect.py --previous data-checkout --output data-next
python tools/build_site.py --data data-next --output build/site
python -m http.server 8080 --directory build/site
```

PowerShell 中先设置 `$env:PYTHONPATH = "$PWD/collector"`，再运行 Python 测试。输出目录必须不存在，避免覆盖源文件或上一次有效数据。

Android：在 `app` 目录运行 `flutter pub get`、`flutter analyze`、`flutter test`、`flutter build apk --release --split-per-abi`。ARM64 包适合现代安卓手机。

## GitHub 初始化

创建公开仓库 garss-next；推送 main 与经过校验的迁移种子 rss-data；在仓库 Settings → Pages 选择 GitHub Actions。第一次运行 Collect RSS and deploy 完成实时采集与发布。来源配置中的 repository 信息、App 的默认 JSON 地址需与实际仓库保持一致。

本项目迁入的源码与素材来自 `https://github.com/chcaty/garss`，不包含历史提交、生成的 README、旧快照、邮件配置、密钥或 SDK 缓存。字体许可证随文件保留。上游根目录未发现统一许可证；迁入并不新增或改变原有文件的授权。

## 来源发现与生命周期

`discovery-sources.json` 配置外部 OPML 目录，目前接入 Plenary 与 awesome-rss-feeds-list 的 19 个目录，覆盖新闻、科学、历史、财经、阅读、摄影、影视、音乐、美食、旅行、体育、建筑、设计、播客等 18 类内容。CI 每 7 天发现一批，单次最多验证 20 个新地址、4 路并发；通过后进入「待确认」，需要在网页加入草稿并提交到 main 才会开启采集。候选最多 100 个，失败验证记录最多 500 条，失败地址 30 天后可重新验证。外部目录失败会保留原候选并在 24 小时后重试。

`api/v1/source-state.json` 保存连续失败次数、首次失败、最近成功和复查时间。连续失败至少 3 次且持续 24 小时后归档，停止普通采集，每 7 天复查；成功后自动恢复。大面积失败（80% 及以上）不累计归档次数，全部活跃源失败则停止发布并保留旧数据。手动停用的源不参与复查。网页「请求复查」生成配置中的 recheck_requested_at，提交生效后立即复查；修改 RSS 地址同样重置归档状态。

归档记录保存在 `api/v1/source-archive.json`，外部发现保存在 `api/v1/source-discovery.json`；两者随 rss-data 滚动保存，不新增历史分支。sources.json 始终保留人工配置，归档仅改变有效采集/阅读目录。归档不是永久删除，网页仍可编辑、复查或删除配置。

来源管理区使用 Headless UI 的 Tabs、Listbox、Menu、Dialog、Checkbox、Switch，支持键盘和焦点管理。草稿保存基线；远程配置变化时先合并远程更新并检查改动，同一字段保留本机值。复制、下载与打开 GitHub 不代表配置已发布。

发现目录现覆盖 18 种分类，轮流分配每类验证名额，优先补足候选较少的类型。目录配置变化会立即触发一次发现，无需等待一周。指定的社交源每次发现都会重试，普通失败地址仍按 30 天冷却处理。

微博热搜与微信 24h 热文通过公开 RSSHub 实例采集；后者来自第三方今日热榜，并非微信官方全站榜单。allow_undated 只用于明确配置的热榜源，缺少发布时间时保存首次发现时间并标记 date_inferred；历史合并保留首次时间，重复采集不把旧条目刷新成新文章。今日头条热点频道暂不可用，保留在发现验证名单，验证通过后进入待确认。

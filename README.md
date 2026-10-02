# GARSS Next

GitHub Actions 采集 RSS，GitHub Pages 展示文章与管理来源，Flutter 手机客户端读取经过校验的 JSON。新仓库不继承旧 Git 历史。

## 目录与语言

- `collector/`：Python RSS 解析、条件请求、并发采集、历史合并和去重。
- `web/`：TypeScript 阅读页与来源管理页；构建成原生 ES modules，无前端框架运行时。
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

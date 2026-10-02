# Product
<!-- impeccable:product-schema 1 -->
## Platform
web
## Product Purpose
用户先高效筛选 RSS 信息，再专注阅读筛选后的内容。桌面和手机都要可用。
## Capabilities and Constraints
GitHub Actions 定时采集 RSS，GitHub Pages 展示信息和管理订阅源，手机读取 JSON。采集数据保存在 rss-data 分支，主分支只保存代码与配置。页面管理修改先保存在本机草稿，提交 GitHub 后生效。Headless UI 和 Tailwind CSS 用于管理界面。持续异常来源归档，候选订阅验证后由用户确认加入。
## Confirmed Experience
用户确认兼顾快速筛选和舒适阅读，提供专注阅读。阅读页隐藏没有文章的来源；管理页提供采集正常筛选；同步状态有可发现的入口。
## Open Decisions
没有要求变更产品名称，统一使用 GARSS。专注阅读使用 RSS 已提供的摘要，原文通过外部链接阅读。

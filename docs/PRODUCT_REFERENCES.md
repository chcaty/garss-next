# 拾阅产品参考

核对日期：2026-10-03（北京时间）。本次使用项目官方文档与仓库提交记录。

| 项目 | 最近提交（UTC） | 本次参考 | 落地方式 |
| --- | --- | --- | --- |
| [FreshRSS/FreshRSS](https://github.com/FreshRSS/FreshRSS) | [2026-10-02T08:16:31Z](https://github.com/FreshRSS/FreshRSS/commit/a4dbc4240d8d0d62ab204ec7d3f68c4dd6e1cb38) | 分类与日期组合筛选 | 网页分类/时间控件及 App 筛选面板 |
| [miniflux/v2](https://github.com/miniflux/v2) | [2026-10-01T09:04:57Z](https://github.com/miniflux/v2/commit/703fe82693ef91054f1163435e2495ed118b3f25) | 键盘阅读与低干扰界面 | J/K 切换、Enter/O 打开、F 收藏、/ 搜索；输入时不拦截 |
| [ReadYouApp/ReadYou](https://github.com/ReadYouApp/ReadYou) | [2026-08-11T17:26:59Z](https://github.com/ReadYouApp/ReadYou/commit/d2b979ccad9a3e54b9499929a9dc2824578b0fd9) | Android 阅读操作层级 | 原生底部筛选面板、保留列表上下文、大字号适配 |
| [RSSNext/Folo](https://github.com/RSSNext/Folo) | [2026-10-02T17:19:31Z](https://github.com/RSSNext/Folo/commit/83c2bad929874938fa82255450311655c3d4a444) | 先组织来源，再消费内容的流程 | 出处/源维护与信息流保持独立入口，阅读端集中筛选 |

分类/日期和快捷键依据：[FreshRSS 筛选说明](https://freshrss.github.io/FreshRSS/en/users/10_filter.html)、[Miniflux 快捷键](https://miniflux.app/docs/keyboard_shortcuts.html)。所有项目在核对时均未归档，提交时间只代表仓库活动。上述落地方式是结合拾阅约束做出的产品判断。

## 提交流程

GitHub 官方支持[通过 URL 预填 Issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-an-issue#creating-an-issue-from-a-url-query)。页面将补丁整理成确认请求，由仓库所有者在 GitHub 提交；Actions 验证所有者、请求格式、逐来源版本和 RSS 地址，正常推送更新，随后显式触发采集。校验失败和冲突保留在请求记录中供修正。GitHub 登录、确认和公开提交记录构成授权证据。

自动应用仅限 sources.json 的允许字段；不会执行 Issue 中的代码，不改变工作流或仓库目标。浏览器不保存凭据。请求采用[queue: max](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)串行处理；使用 [GITHUB_TOKEN 的 workflow_dispatch 例外](https://github.blog/changelog/2022-09-08-github-actions-use-github_token-with-workflow_dispatch-and-repository_dispatch/)启动收集，避免依赖不会自动触发的 bot push。

# 行为保持重构记录

本轮使用 refactor，Android 结合 flutter-expert，React 结合 vercel-react-best-practices。先运行基线测试，补充关键行为断言，再分三批实施。现有产品、界面和本机数据规则沿用 PRODUCT.md、DESIGN.md；未增加依赖或修改数据格式。

## 检查结果与范围

| 模块 | 发现 | 收益／风险 | 本轮处理 |
| --- | --- | --- | --- |
| Android `ui/home.dart` | 918 行混合导航、阅读、文章行、来源、设置和排序；各页局部筛选与全局阅读状态已分开 | 高收益、低风险 | 保留导航外壳，按现有页面和文章行拆文件；纯排序移至数据层 |
| Android `state/library.dart` | 不可变状态、查询和 Riverpod 控制器混在同一文件；总数与未读数重复遍历来源归属 | 中收益、低风险 | 提取 `library_state.dart`，合并计数遍历；保留控制器及串行写入队列 |
| React `sync.tsx` | 数据请求、状态优先级、筛选分页、四个区块集中在密集 JSX 中 | 高收益、中低风险 | 分离挂载、页面状态、请求 Hook、纯状态函数和展示区块；用原页面 DOM 基线保护输出 |
| Python `tools/collect.py` | CLI 参数、采集编排和上一批快照文件操作混在入口函数 | 中收益、低风险 | 拆开参数解析和执行；快照模块负责读取上一批文档、保留上一份不可变快照 |
| React `sources.tsx` | 公共配置读取、草稿恢复、冲突确认、编辑、批量操作与多个弹窗仍集中在 Manager | 高收益、高风险 | 暂缓整体拆分；现有补丁、冲突合并和发布判定已有独立纯模块 |
| Python `fetch.py`、`discovery.py` | 重试／时间预算／缓存更新，以及发现名额／冷却策略在较长函数内联动 | 中收益、高风险 | 保留策略与执行顺序，避免同时改动采集边界 |

没有统一跨端状态模型：公共配置、有效采集目录、采集健康、本机关注和带版本基线的草稿承担不同职责。同步页与草稿页的归档判定也有不同上下文，不能仅因表达式相近就合并。收藏分类的启动补齐与新增收藏快照时机不同，本轮保留两条路径。

## 实施后的边界

- Python：`collect.main()` 保留 CLI 入口，`parse_arguments()` 处理参数，`collect(args)` 按原顺序编排。`snapshot.read_previous_document()` 保留缺失文档的默认值和无效 JSON 的异常；`retain_previous_snapshot()` 校验后仅复制上一份快照。全源失败停止输出、新目录约束、离线种子、归档阈值、缓存、发现、同步记录、最终校验和发布流程沿用原行为。
- Web：`sync.tsx` 只挂载；`sync-page.tsx` 持有筛选、搜索、分页和五个独立请求；`use-published.ts` 保留请求取消标记、重试与已成功数据；`sync-model.ts` 判定状态和组合筛选；`sync-sections.tsx` 展示最近同步、来源状态、批次和发现。所有组件在模块顶层声明，保留原来的来源顺序、20 条分页、缺失健康状态显示、DOM、链接与文案。Tailwind 显式扫描新文件。
- Android：`home.dart` 从 918 行减至 175 行，保留底栏／侧栏与同一个 `IndexedStack`；`reading_page.dart`、`article_row.dart`、`sources_page.dart`、`settings_page.dart` 分别承担现有视图。`data/reading_order.dart` 保留来源轮换算法。`library_state.dart` 负责不可变阅读状态、计数与查询；控制器仍负责加载、迁移、刷新和有序持久化。原 `home.dart` 和 `library.dart` 继续导出原有公共类型／函数，避免调用方导入失效。

## 验证

基线：Python 53 项、Web 21 项、Flutter 27 项通过。新增采集入口测试与 Web DOM 基线先在拆分前实现上通过，再用于回归；拆分后增加同步状态函数测试，扩充 Android 计数断言。

| 检查 | 结果 |
| --- | --- |
| Python unittest 全量 | 57 项通过；新增采集入口离线历史／别名、上一份快照保留、全源失败停止、输出目录保护、正常发布记录断言 |
| Python compileall、sources 校验 | 通过 |
| 采集 JSON 比对 | 固定时间、相同历史与模拟响应，离线 14 个、正常发布 15 个 JSON 文件与原实现逐字节一致，包含不可变快照、manifest 和发布记录 |
| Web TypeScript | `npm run check` 通过 |
| Web 测试 | 26 项通过；覆盖原有契约与草稿／发布行为，增加同步状态优先级、组合筛选和三种真实组件渲染基线 |
| Web DOM 比对 | 正常数据、健康状态缺失、来源目录缺失三种状态的 React 输出 SHA-256 与拆分前一致 |
| Web 生产构建 | `npm run build` 通过 |
| Flutter 格式、静态分析 | 格式无变更，`flutter analyze --no-pub` 无问题 |
| Flutter 全量测试 | 27 项通过，生成 coverage；保留离线收藏、迁移、独立筛选、撤销、来源关注、大字号与宽屏等 Widget 回归，扩充总数／未读数断言 |
| Android 构建 | `flutter build apk --debug --no-pub` 通过，输出 `app/build/app/outputs/flutter-apk/app-debug.apk` |
| 差异检查 | `git diff --check` 通过 |

Python 使用项目 `.venv`。测试中的网络和采集响应使用模拟数据；Git 发布测试只操作临时本地仓库，验证过期写入拒绝。Web DOM 测试使用真实 React 组件树，模拟请求和浏览器外观读取。Flutter 使用 Widget 测试。本轮未实际触发线上采集、提交来源请求或部署，也未进行真机性能测量。

## 剩余问题

1. `sources.tsx` 的 Manager 仍承担多个交互流程。下一轮应先补充编辑／导入、同字段冲突、逐批 GitHub 确认和实际发布完成的浏览器回归，再按流程拆分。
2. Android 阅读页构建仍超过 300 行，控制器启动时的缓存／收藏迁移仍较集中。可继续提取阅读工具栏与存储解析，但需要保留页面状态、保存失败提示与异步刷新期间的用户修改。
3. 本轮保持 Web 同步页原有状态优先级和旧快照兼容行为；若需要统一各入口对公共停用／归档的展示，应作为独立产品变更处理。
4. 完整自动化浏览器交互与线上工作流验证仍未覆盖；DOM 基线无法单独证明异步交互或真实网络行为。

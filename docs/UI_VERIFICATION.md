# 界面改进与验证记录

验证日期：2026-10-05。沿用 PRODUCT.md 的筛选后阅读定位与 DESIGN.md 的阅读目录方向。

## 本轮完成

- Web 分离阅读范围与未读条件，手机收起来源／分类／时间／排序，保留搜索、未读和可移除筛选标签；桌面继续提供来源索引。
- Web 与 Android 固定专注阅读队列，标明本次筛选位置；Web 返回列表恢复滚动及触发文章焦点。
- 两端移出稍后读提供 8 秒撤销，恢复删除前内容和分类，不覆盖其他收藏或之后重新保存的版本。
- Web 以公共订阅命名来源配置，审查按核对改动／GitHub 提交／检查发布结果组织；手机整页审查，关闭入口固定，备份默认折叠。
- Android 阅读来源使用可搜索的原生面板，本机关注范围可与采集状态组合；批量已读按钮标明当前结果数量。
- Web 发布时间、来源目录、健康状态、采集批次、发现状态分别加载和重试；未知数量显示 —。Android 保留同批次报告和缓存回退，补充加载语义、异常空状态恢复操作与折叠采集说明。

## 自动检查

| 检查 | 结果 |
| --- | --- |
| npm run check | 通过 |
| npm test | 21 项通过 |
| npm run build | 通过 |
| flutter analyze --no-pub | 无问题 |
| flutter test --no-pub --coverage | 27 项通过，生成 app/coverage/lcov.info |
| flutter build apk --debug --no-pub --build-number=4005 | 通过 |
| git diff --check | 通过 |

新增回归覆盖过期收藏撤销、其他收藏和后续重新保存的保护、详情内撤销、关注与健康组合、来源面板搜索。控件测试覆盖 360px、1024px、横屏和 200% 字号。

## 页面与模拟器验证

Web 使用 Codex 内置浏览器与本地构建，390 × 844 和 1440 × 1000 视口，验证浅色／深色、来源搜索、未读组合、独立筛选、收藏撤销、队列切换、返回焦点与滚动、空筛选恢复、来源字段审查和区块重试。手机首篇文章行顶部约 443px，首篇完整标题在 544px 内可见。检查页面无横向溢出，来源复选框触摸区域为 44px。

本地使用 data-next 历史快照；其中健康、采集历史、发现状态文件缺失，用于验证部分失败和未知数量。此结果不代表线上服务异常。来源审查验证使用临时本机草稿，已丢弃；没有提交 GitHub 请求。

Android 使用 Pixel_10_Pro_XL 只读模拟器，最终调试 APK。手机 390dp 宽，宽屏约 1365 × 1067dp；验证浅色／深色、130% 系统字号、底栏／侧栏、来源面板、稍后读空筛选、收藏撤销、来源管理、同步记录与固定阅读队列。截图来自 Android 模拟器，不是 Flutter Web。尚未进行真机手势、TalkBack 和性能采样。

截图保存在本地忽略目录 build/screens，包含：

- [Web 手机信息流](../build/screens/ui-web-phone.jpg)
- [Web 手机筛选](../build/screens/ui-web-filter-phone.jpg)
- [Web 手机阅读](../build/screens/ui-web-focus-phone.jpg)
- [Web 手机空状态](../build/screens/ui-web-empty-phone.jpg)
- [Web 手机整页来源审查](../build/screens/ui-web-review-phone.jpg)
- [Web 手机同步部分失败](../build/screens/ui-web-sync-phone.jpg)
- [Web 深色桌面](../build/screens/ui-web-dark-desktop.jpg)
- [Android 手机](../build/screens/ui-app-phone.png)
- [Android 深色手机](../build/screens/ui-app-dark-phone.png)
- [Android 来源面板](../build/screens/ui-app-source-picker.png)
- [Android 手机专注阅读](../build/screens/ui-app-focus-phone.png)
- [Android 深色空状态](../build/screens/ui-app-empty-dark-phone.png)
- [Android 深色宽屏来源](../build/screens/ui-app-sources-dark-wide.png)
- [Android 深色宽屏阅读](../build/screens/ui-app-focus-dark-wide.png)

最终调试包：`app/build/app/outputs/flutter-apk/app-debug.apk`（仅用于本轮验证，产品版本配置未改变）。

## 平台差异

Web 保留鼠标、键盘、桌面索引、外部原文与公共配置管理；Android 保留 Material 组件、系统返回、下拉刷新、底部面板、本机关注、字号／图片设置及应用内原文。没有引入账号后端、跨端阅读记录同步或 Web 离线启动保障。

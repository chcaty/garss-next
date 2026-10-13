# 拾阅 Android

Android 优先的 Flutter 阅读客户端，直接读取 `https://chcaty.github.io/garss-next/api/index.json`，不需要另建业务服务器。

支持来源轮换或最新排序、来源开关、搜索、未读筛选、收藏、字号与图片设置、下拉同步、摘要阅读及应用内原文网页。服务端提供最近 30 天文章，并为每个源保留至少最近 5 篇可用文章；收藏保留文章元数据与摘要，即使文章退出服务端目录也不会删除。目录、收藏、摘要和个人偏好仅存本机；原文与图片来自出版者，需要网络，不提供跨设备账号同步。

阅读与收藏在页面切换时各自保留搜索和未读筛选（本次打开期间），来源筛选只影响阅读页。空结果可一键重置；关闭当前来源后自动回到全部关注来源。可将当前筛选结果全部标为已读，并通过提示条撤销此次变更。来源页显示关注数量，设置页实时预览字号；宽屏阅读区域限制为 760 个逻辑像素。

## 运行与安装

使用 Flutter 3.47.2 / Dart 3.13.2，已提交 `pubspec.lock`。在本目录运行：

```powershell
flutter pub get
flutter analyze
flutter test --coverage
flutter run
flutter build apk --release --split-per-abi
```

APK 位于 `build/app/outputs/flutter-apk/`，按处理器架构分别生成，避免一个安装包包含三套运行库。现代安卓手机优先安装 `app-arm64-v8a-release.apk`；旧款 32 位 ARM 设备使用 `app-armeabi-v7a-release.apk`；x86_64 模拟器使用 `app-x86_64-release.apk`。需要全架构通用包时，可运行 `flutter build apk --release`。

这是供直接安装测试的预览版，当前 release 构建使用 Android debug 签名，不应上传商店；正式发行需设置受保护的签名密钥。不同构建机器的 debug 签名可能不同，跨机器预览包覆盖安装可能需要先卸载，卸载会删除本机记录。

`.github/workflows/android.yml` 会在 App 修改或手动运行时完成分析、测试和 APK 构建，并提供 `garss-android-preview` 下载产物。

文章数据按 `.github/workflows/collect.yml` 的配置每天北京时间 06:00、13:00、17:00、22:00 启动抓取，发布完成后可同步到 App。App 启动读取本机缓存后自动同步，也支持下拉刷新与同步按钮；没有后台定时同步。外部发现目录通常每 7 天刷新一次；过期候选的重新验证会独立检查，不依赖固定星期的 App 更新。

可通过 `--dart-define=GARSS_BASE_URL=https://your-host/path/` 在构建时替换数据站点。站点必须提供相同的 v1 契约；客户端限制所有快照端点在相同站点的 API 目录内。

## 数据与安全

客户端发现版本后读取 `meta.json`、快照 manifest 及两个快照文件，验证 SHA-256、字节数、快照身份与生成时间。部署过程中快照旋转会重新发现一次；同步失败保留上一份有效目录与阅读记录。

`lib/data` 负责模型和快照读取，`lib/state` 使用 Riverpod 管理不可变状态和串行本地保存，`lib/ui` 提供列表、摘要、原文、来源和设置。摘要仅显示纯文本；只有 HTTP(S) 链接允许在原文视图导航。为兼容历史来源，出版者原文和图片允许 HTTP；数据站点默认 HTTPS。

Logo 使用项目统一的打开书页与书签图标。`assets/editorial-heading.ttf` 为仓库自托管 Noto Serif SC 标题字体子集，许可证见 `assets/OFL.txt` 与原始 `docs/assets/fonts/README.md`。

## 本机记录恢复

稍后读 JSON 整体或任意一条记录损坏时，App 保留原始 `saved-v2`，只展示可读取的收藏，并显示持续的恢复提示。此时稍后读改动仅在本次会话有效，阅读、关注和设置不会覆盖原始收藏。点击「恢复可读收藏」并确认后，先将完整原文写入新的 `saved-v2-quarantine-*` 本机备份，再保存当前可读收藏；备份或替换失败均会提示，失败时不会解除保护。备份不会被后续恢复覆盖，但卸载 App / 清除应用数据仍会删除备份。

旧收藏补齐分类也采用先备份再替换；中断后可重新启动继续升级。存储读取异常时停止覆盖相应记录；存储写入返回失败或抛出异常时会明确显示当前改动未保存。

订阅源的「只看本机关注」和开关只表示本机关注意愿。自动归档、公共停用的来源仍可关注或取消关注；是否进入信息流仍由有效采集状态、有无文章和本机关注共同决定。

## 同步与列表性能

当前进程已完整校验过的快照，在 index、meta 与 manifest 的身份、生成时间、同站点端点、字节数和 SHA-256 合同全部相同时，可以复用已验证的目录对象，不再重复下载快照正文或保存同一目录。仅磁盘缓存或相同 snapshot_id 不足以跳过校验；冷启动仍会下载和验证。轮换重试一次和 v1 完整性检查保持不变。

Android / 原生端的快照校验、JSON 解析、模型构造和收藏／目录 JSON 序列化通过 compute 在独立 isolate 中执行。列表预计算搜索文本、来源计数和时间戳，缓存已排序的稍后读与分类；相同时间保留输入顺序。Flutter Web 的 compute 不保证独立 isolate。

可运行 `dart --suppress-analytics run tool/benchmark_library.dart feeds.json articles.json output.json` 复现目录模型 CPU 测试。输入应为同一公开批次的 v1 文件；输出包含每个查询的有序 ID，便于比较成员与顺序。此测试不衡量手机帧率、耗电或真实网络速度。

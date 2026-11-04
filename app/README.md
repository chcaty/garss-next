# 嘎!RSS Android

Android 优先的 Flutter 阅读客户端，直接读取 `https://chcaty.github.io/garss-next/api/v1/app/meta.json`，不需要另建业务服务器。

支持来源轮换或最新排序、来源开关、搜索、未读筛选、收藏、字号与图片设置、下拉同步、摘要阅读及应用内原文网页。App 仅下载最近 5 个自然日（含今天，Asia/Shanghai 北京时间）的文章，不补齐低频来源旧文。网页与采集器仍保留原有 30 天目录及每源至少 5 篇策略；收藏保留文章元数据与摘要，即使文章退出服务端目录也不会删除。目录、收藏、摘要和个人偏好仅存本机；原文与图片来自出版者，需要网络，不提供跨设备账号同步。

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

`.github/workflows/android.yml` 会在 App 修改或手动运行时完成分析、测试和 APK 构建，并提供 `shiyue-android-preview` 下载产物。

文章数据按 `.github/workflows/collect.yml` 的配置每天北京时间 06:00、13:00、17:00、22:00 启动抓取，发布完成后可同步到 App。App 启动读取本机缓存后自动同步，也支持下拉刷新与同步按钮；没有后台定时同步。候选订阅目录每周日北京时间 11:30 更新。

可通过 `--dart-define=GARSS_BASE_URL=https://your-host/path/` 在构建时替换数据站点。站点必须提供相同的 v1 App 契约；客户端限制所有文章快照端点在相同站点的 `api/v1/app/` 目录内。App 不会回退下载 30 天文章接口；同步记录页仍读取原有采集记录与来源状态。

## 数据与安全

客户端直接读取 `api/v1/app/meta.json`，再读取快照 manifest 及两个快照文件，验证保留策略、SHA-256、字节数、快照身份与生成时间。已有通过校验的本机缓存且快照 ID 未变时，只请求 meta，不重复下载数据。响应以流式方式读取并限制实际接收字节数（meta/manifest 64 KiB，feeds 4 MiB，articles 20 MiB；数据文件同时受 manifest 声明大小限制），超限或超时立即取消。部署过程中快照旋转会重新发现一次；同步失败保留上一份有效目录与阅读记录。

本机目录使用带 SHA-256 和字节校验的双槽缓存，完整写入新槽后才切换提交指针；损坏时可恢复另一槽。升级时原 `catalog-v1` 缓存仍可离线阅读，首次成功同步 5 天快照后才清理旧大缓存。收藏、已读和个人偏好不参与目录替换。

`lib/data` 负责模型和快照读取，`lib/state` 使用 Riverpod 管理不可变状态和串行本地保存，`lib/ui` 提供列表、摘要、原文、来源和设置。摘要仅显示纯文本；只有 HTTP(S) 链接允许在原文视图导航。为兼容历史来源，出版者原文和图片允许 HTTP；数据站点默认 HTTPS。

Logo 复用仓库既有 RSS 图标。`assets/editorial-heading.ttf` 为仓库自托管 Noto Serif SC 标题字体子集，许可证见 `assets/OFL.txt` 与原始 `docs/assets/fonts/README.md`。

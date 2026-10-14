# Web 开发依赖安全维护

核对日期：2026-10-14。基于可靠性改进分支 `b2364cff`。

## 问题与最小修复

`npm audit` 的 4 个 high 条目来自同一条开发依赖链：

```text
@tailwindcss/cli 4.3.3
└─ @parcel/watcher 2.5.1
   └─ micromatch 4.0.8
      └─ braces 3.0.3
```

[GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm)
涉及深层嵌套模式触发栈耗尽；核对时 `braces` 没有已发布的修复版本。
生产依赖审计原本为 0。它不表示已发现网页阅读数据可以触发该问题。

保留现有 Tailwind CLI 4.3.3，只在其依赖范围内把 `@parcel/watcher`
固定为官方 2.6.0。该版本改用 `picomatch`，移除 `micromatch` / `braces`
依赖链。没有使用 `npm audit fix --force`、降级 Tailwind 或隐藏告警。

- [官方 watcher 2.6.0 依赖](https://github.com/parcel-bundler/watcher/blob/v2.6.0/package.json)
- [官方 watcher 2.6.0 包装层](https://github.com/parcel-bundler/watcher/blob/v2.6.0/wrapper.js)
- [npm overrides 说明](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/#overrides)

锁文件只更新 watcher 及其传递依赖树，保留无关依赖记录。最终解析为
`@parcel/watcher 2.6.0`、`picomatch 4.0.7`、`detect-libc 2.1.2`。
后续更新 Tailwind CLI 时，重新核对上游 watcher 要求和审计结果；上游采用
安全版本后，应删除该临时 override，并重新运行以下检查。

## 可复现验证

在项目根目录、Node.js 24 下运行：

```sh
npm ci --ignore-scripts
npm ls --all
npm audit
npm audit --omit=dev
npm run check
npm test
npm run build
```

本次在 Linux x64 / glibc、Node 24.19.0、npm 11.9.0 验证：

- 干净安装成功，安装前后锁文件 SHA-256 不变。
- 完整依赖审计从 4 high 降为 0，生产依赖审计保持 0。
- TypeScript 检查、79 个 Web 测试及正式构建通过。
- 新增真实 Tailwind CLI `--watch=always` 测试：首次输出、修改已有文件、
  新增文件均生成相应 CSS；结束后清理进程与临时文件。
- 修复前后 `web/build` 所有产物逐字节一致。
- 另外复跑 83 个 Python 测试及公共来源配置校验，均通过。

普通构建不启用 watcher，所以单独验证 watch 模式，避免只用构建成功推断
原生模块兼容性。没有验证其他操作系统或 CPU 的原生 watcher；2.6.0 不再
提供 Windows ia32 预编译包，现有 Tailwind oxide 也没有原生 ia32 包。
此改动不涉及 Python / Flutter 源码、公共来源、采集、部署或签名配置。

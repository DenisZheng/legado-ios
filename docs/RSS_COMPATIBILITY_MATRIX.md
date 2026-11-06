# RSS 兼容验证矩阵

配套计划：[RSS_COMPATIBILITY_PLAN.md](RSS_COMPATIBILITY_PLAN.md)。本文件先建立验证规范和能力场景，不代表 307 个真实源已经执行。

## 结果与证据

每条源、每个阶段独立记录以下状态：

- `PASS`：在记录的提交/设备上实际完成，附证据。
- `FAIL`：已执行并复现缺陷，附首个失败阶段、原因和关联任务。
- `NOT_RUN`：未执行，或上游失败导致没有执行；说明前置原因。
- `NEEDS_LOGIN`：需要用户完成登录或人工输入，后续步骤仍为 `NOT_RUN`。
- `UNSUPPORTED`：确认实现不支持所需能力，注明 API/格式。
- `NOT_APPLICABLE`：源不包含该能力，排除出该阶段分母。

证据类型分开列出：`contract`（对照源码的行为测试）、`fixture`（合成服务链路）、`live-feed`（公开 XML 端点检查）、`live-source`（实际规则执行）、`device`（iOS 页面或真机操作）。不能把 `contract/fixture/live-feed` 自动升级为真实源通过。

## 当前已有证据

| 范围 | 证据 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| `10afd1e` 核心/页面模型 | [CI 42206209681](https://github.com/DenisZheng/legado-ios/actions/runs/42206209681)，385 tests / 49 suites | 当前包回归通过 | 307 源可用、全部 WKWebView 集成通过 |
| `10afd1e` RSS UI | 同一 CI，3 项通过 | 入口/默认页、Files 导入、搜索分页及阅读收藏的合成链路 | 线上登录、媒体播放、真机 Cookie 策略 |
| 少数派/异次元公开 feed | [在线检查 42177537134](https://github.com/DenisZheng/legado-ios/actions/runs/42177537134)；[夹具说明](../Tests/LegadoCoreTests/Fixtures/RealWorldRSS/README.md) | 当次端点返回正常 RSS XML；合成 XML 可默认解析 | 用户完整规则、JS、正文或视频播放 |
| `WebReaderBridgeTests` | 测试代码已存在 | 有可执行的页面变量/分析器回归 | 本轮 CI 未执行该 Scheme，不能标通过 |

## 能力场景

每行是最小验收场景，不是实际源。实现时复用已有测试文件和本地服务；只有场景确实需要新的边界才增加测试组件。

| 场景 ID | 对应任务 | 输入/操作 | 关键断言 | 建议验证位置 |
| --- | --- | --- | --- | --- |
| C01 | P0-01 | cache 限时写入、读取、再次 JS 求值、到期 | 限时值不进入永久内存缓存；到期返回 null | `JavaScriptRuleEvaluatorTests`、缓存单元回归 |
| C02 | P0-01 | 显式内存值、不限时持久值、`onlyDisk`、覆盖/删除 | 显式内存与磁盘语义保持；限时覆盖清理旧内存值 | 同上 |
| C03 | P0-02 | setContent/setBaseUrl/setRedirectUrl，重定向到另一域/目录 | 链式调用、URL/null、空值和数据地址行为；解析链接基准正确 | `JavaScriptRuleEvaluatorTests`，页面桥集成 |
| C04 | P0-03 | GET/POST/HEAD；Header 分别传对象/JSON 字符串 | 请求头、正文、超时、不跟随重定向；规则/页面返回形态各自对齐 | 注入 mock transport；`WebReaderBridgeTests` |
| C05 | P0-04 | 静态/@js/<js> Header，登录头，URL headers | 大小写冲突和合并优先级；登录页也应用动态头 | 网络单元回归，登录页集成 |
| C06 | P0-04 | 模板、动态分类、POST、charset/bodyJs | 最终 URL、字节编码和页码正确；错误可见 | `LegadoURLBuilder` 与 RSSService 回归 |
| C07 | P0-05/06 | 登录写 Cookie → 列表 → 正文 → 页面更新 Cookie → 再请求 | 两套 Cookie Store 显式同步；注销/开关/并发正确 | 本地服务 + WKWebView + 登录类源真机 |
| C08 | P0-06/11 | loginUi 表单、响应 loginCheckJs、取消验证码/浏览器 | 正确等待和继续；取消/失败可区分；不伪造验证成功 | 页面模型、UI、需人工操作的实际源 |
| C09 | P0-07/08 | 顶层与函数式 WebView，preload/inject/startHTML | 请求/回调/变量完整；超时取消；远程页面没有特权桥 | WKWebView 集成与来源边界回归 |
| C10 | P0-09 | Referer/UA/Cookie 图片、Range 媒体、跨域跳转 | 主文档和子资源分别检查；200/206/失败、取消均正确 | 本地资源服务器 + 真机 |
| C11 | P0-10 | 已知 AES 密文向量、实际源 transformation | 输出与 Android 向量一致；错误 key/iv/模式明确失败 | 加密单元回归与源最小规则 |
| C12 | P0-12/13 | 实际调用的文件/工具 API | 返回值、编码、异常、清理和资源范围 | 按 API 单独增加最小夹具 |
| C13 | P0-14/P1-03 | 页面/播放器进入全屏、锁方向、关闭、返回 | 原方向和页面恢复、没有残留播放 | iOS 15 和较新系统，iPhone/iPad |
| C14 | P1-01/02 | MP4、HLS 主/子列表、分片/key、签名 URL | 正确选播放输入并带头；续请求可播放；错误可见 | 本地媒体夹具 + 原生播放器 + 实际源 |
| C15 | P1-04/05/07 | 播放、倍速、拖动、退出、重启、收藏/历史重新进入 | 时间单位一致、位置恢复；不重复记录；直播不按点播续播 | repository/页面模型 + 播放器 UI |
| C16 | P1-06 | MPD URL 与规则返回 XML | 记录支持范围/明确不支持及替代方案；不算 HLS 通过 | 独立平台评估记录 |
| C17 | P2-01/04 | 长图、图集切换、缩放、保存、拒绝权限 | 顺序/当前项/手势正确，保存结果可见 | RSS 图片 UI + 真机相册 |
| C18 | P2-02/05 | 长文懒加载、滚动、关闭重开、旋转 | 图片完成后位置仍正确，源脚本不被破坏 | WebView 集成 + UI |
| C19 | P0-15/P2-03 | nextContentUrl 单链、多链接、重复/回环、第二页失败 | 有限请求、有序正文、不丢页；刷新取消/重试行为明确 | RSSService 注入 transport + 页面模型 |
| C20 | P0-15/P1-07/P2-05 | 导入/编辑/导出/重启，历史开关 | 字段和位置不丢失；全局开关与源字段规则明确 | 导入/持久化/页面模型 |

## 真实源记录格式

原始源集合和执行结果放在已忽略的 `artifacts/rss-compat/`。仓库只保存脱敏摘要、可公开的最小规则和合成响应；不上传 Cookie、Token、账号和完整文章。

建议每次运行保存：

```text
artifacts/rss-compat/<run-id>/
  manifest.json       # 集合指纹、Android/iOS 提交、设备/系统、运行时间和数量
  source-index.json   # 本地 source_id 与源的映射，不公开原始私有 URL
  results.csv         # 每源每阶段一行，首次执行前均为 NOT_RUN
  evidence/          # 本地截图和脱敏失败日志
```

CSV 列约定：

```csv
run_id,source_id,capabilities,stage,status,evidence_type,android_result,ios_commit,device,reason,task_id,evidence_path
```

- `stage` 固定为 `import/sort_search/refresh/article_parse/content/image/video/persistence`。用户要求的导入、刷新、文章解析、正文和视频必须保留独立结果。
- `source_id` 根据本地稳定身份生成；重复源如何合并先记录规则，保留原始数量与去重后数量。不要因为用户曾说“307”就强制生成 307 行或丢弃额外条目。
- `capabilities` 可包含 `plain-feed/dom/js/login/webview/image/hls/mpd/file/crypto`，用于选择代表源，不代表这些能力已通过。
- Android 结果须带实测版本与时间；仅阅读代码时填写 `NOT_RUN`，不能把“用户以前验证有效”当成本次差分结果。
- `reason` 记录首个可定位问题，如 API 缺失、HTTP 状态、规则为空、网站不可用。每个下游阶段继续保留 `NOT_RUN` 和前置失败原因。
- 同一 source 的修复前后结果保持两个运行记录，不覆盖失败证据。
- 汇总每阶段的 PASS/FAIL/NOT_RUN/NEEDS_LOGIN/UNSUPPORTED 数量；只在有明确分母时给通过率。

## 执行方法

1. 先运行不联网的契约回归。首次失败定位到任务 ID；修复后保留测试。
2. 运行本地服务和对应 UI/WKWebView 集成，检查跨层行为。页面桥测试与 RSS UI Scheme 分别执行。
3. 从实际集合选代表源，保留完整原规则在本地执行，记录每阶段结果；不要拿删掉 JS 的简化 manifest 代替原源。
4. 补登录/媒体等需要真机或人工交互的场景，再扩展到全集合。联网失败标记环境与时间，避免反复重试产生无意义请求。

macOS 的针对性入口（按改动范围选取）：

```sh
swift test --disable-sandbox --filter JavaScriptRuleEvaluatorTests
swift test --disable-sandbox --filter JavaScriptRuleCacheTests
swift test --disable-sandbox --filter RSSRegressionTests
swift test --disable-sandbox --filter RSSLibraryRegressionTests
xcodebuild -project Legado.xcodeproj -scheme LegadoReaderTests \
  -destination 'platform=iOS Simulator,id=<UUID>' \
  -only-testing:LegadoReaderTests/WebReaderBridgeTests CODE_SIGNING_ALLOWED=NO test
```

RSS UI 本地服务、Files 夹具和完整验证见 [开发指南](DEVELOPMENT.md)。新增测试尚未提交/执行时，记录为待验证，不能引用历史绿色 CI 证明它通过。

## 本轮记录

| 场景 | 状态 | 证据 |
| --- | --- | --- |
| C01/C02 | 待补回归与执行 | Android 源码已核对；iOS TTL 读回路径存在丢期限问题 |
| C03～C20 | 按各任务继续 | 既有测试见文件，不宣称完成本轮所有场景 |
| 真实源逐条矩阵 | NOT_RUN | 尚未定位完整源集合；本文只是记录规范和能力场景 |

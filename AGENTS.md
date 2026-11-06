# AGENTS.md

## 协作约定

- 作为资深全栈工程师、软件架构师和对等技术协作者工作，默认使用简体中文。
- 先给判断和核心理由，再解释必要细节；不使用汇报腔、客服腔或重复性总结。
- 优先级：安全性 = 正确性 > 最小改动 > 可读性 > 一致性。
- 项目内规则冲突时：用户明确要求 > 本文件 > 局部项目约定 > 通用最佳实践。
- 先从代码、文档和历史还原真实需求；技术判断与项目事实冲突时直接指出，无法自行解决的歧义才询问用户。
- 从实际约束推导方案。重要设计先检查反例、边界条件和失败模式，区分项目证据与惯例。
- 只修改与当前任务直接相关的内容；不顺带重构、清理或删除既有代码，仅删除本次修改产生的无用代码。
- 保持现有架构、目录、公开接口和技术选型；确需改变时先说明原因并取得确认。
- 优先使用现有依赖、标准库和原生能力。新增依赖、改变运行时或引入复杂抽象前说明必要性，不为假设的未来需求预先抽象。
- 注释、文档优先中文，专有名词和 API 名保持原文；提交消息必须使用中文。
- 新增和修改文件使用 UTF-8 无 BOM、LF 换行。
- 不可恢复的错误及时失败，不使用空 `catch`、吞异常或伪造成功状态。日志仅记录必要输入、分支、状态变化和异常，避免敏感数据。
- 跨层规则同步修改，包括校验、文案、权限、数据格式和 API 契约。

## 仓库与工作方向

本项目是「小浣熊阅读」，兼容 Android 阅读（Legado）书源的 iOS 阅读器。

- Fork：`https://github.com/DenisZheng/legado-ios`，当前 Git remote `origin` 指向此仓库。
- 上游：`https://github.com/Aminark/legado-ios`。执行 GitHub CLI 操作时显式指定 `--repo`，不要混淆 Fork 和上游。
- RSS 工作分支：`feature/rss-navigation-compat`，跟踪 `origin/feature/rss-navigation-compat`。开始工作先检查分支、工作区和远端状态，保留已有修改。
- 现有草稿 PR：[恢复 RSS 底部入口并增强 Android RSS 规则兼容](https://github.com/DenisZheng/legado-ios/pull/1)，目标为 Fork 的 `main`。PR 状态和提交范围以实时查询为准。
- 用户指定的 Android 基准位于 `E:\Projects\legado`。默认仅用于阅读和行为对照，不修改该仓库。换机器时确认其位置，不把此路径写入产品运行逻辑。
- 初始化时 Android 基准提交为 `330e606c4`；后续对照应记录当时实际提交，不能把不同版本的实现混为一谈。

当前目标是让 Android 基准的 RSS 源在 iOS 上能够正常导入、解析并使用。RSS 底部入口已经存在，后续工作应沿现有链路补齐兼容行为，并用具体源规则和回归用例证明结果。

## 阅读顺序与技术约束

先阅读 `README.md`、`CONTRIBUTING.md` 和 `docs/DEVELOPMENT.md`，再定位当前任务涉及的模块。

- Swift 6、SwiftUI、UIKit、WebKit；App 最低支持 iOS 15，核心包声明支持 macOS 14。
- `Package.swift` 定义 `LegadoCore`、`LegadoAppModels` 及其测试；依赖由 `Package.resolved` 锁定。
- 核心解析复用 SwiftSoup、Kanna、JavaScriptCore，持久化使用 SQLite；不要另建平行的 RSS 规则引擎或数据库体系。
- App 工程为 `Legado.xcodeproj`，主 Scheme 为 `Legado`。新增 Swift 文件时，同时检查 Swift Package 与 Xcode target 的源文件配置；包测试通过不代表 App target 已包含该文件。
- App 与 Package 的编译上下文不同，部分页面模型使用 `#if SWIFT_PACKAGE` 导入 `LegadoCore`。修改访问级别和模块引用时检查两条构建路径。
- 新增系统 API 要保留 iOS 15 路径，复用 `App/Compatibility.swift` 中的兼容封装。
- 页面状态沿用 `@MainActor` 页面模型，持久化沿用现有 repository / actor。异步刷新、分页和源切换不得让过期请求覆盖当前页面。

## RSS 代码地图

| 职责 | 主要文件 |
| --- | --- |
| 底部入口、默认首页 | `App/RootTabView.swift`、`App/Features/Settings/OtherSettingsView.swift` |
| 应用模型装配、导入深链接 | `App/LegadoApp.swift`、`App/Info.plist`、`Sources/LegadoCore/Import/RuleImportInput.swift` |
| RSS 管理、分类、文章、导入 UI | `App/Features/RSS/RSSViews.swift` |
| 导入、刷新、分页、收藏、阅读记录 | `App/Features/RSS/RSSLibraryModel.swift` |
| 源编辑、调试 | `App/Features/RSS/RSSSourceEditorView.swift`、`App/Features/RSS/RSSSourceDebugView.swift`、`Sources/LegadoCore/Debugging/RSSSourceDebugger.swift` |
| 源和文章数据契约 | `Sources/LegadoCore/Domain/RSSModels.swift` |
| JSON 解码、订阅清单、合并 | `Sources/LegadoCore/Import/RSSSourceImporter.swift` |
| 分类、请求、默认 RSS/Atom 与自定义规则解析 | `Sources/LegadoCore/RSS/` |
| 通用规则与 JavaScript 兼容 | `Sources/LegadoCore/RuleEngine/RuleEngine.swift`、`Sources/LegadoCore/RuleEngine/JavaScriptRuleEvaluator.swift`、`Sources/LegadoCore/RuleEngine/JavaScriptRuleCache.swift` |
| 请求模板和请求头 | `Sources/LegadoCore/Networking/LegadoURLBuilder.swift`、`Sources/LegadoCore/Networking/BookSourceHeaderResolver.swift` |
| 正文模式、HTML 处理、原生桥接 | `Sources/LegadoCore/RSS/RSSReadingPolicy.swift`、`App/Features/RSS/RSSWebReaderView.swift` |
| RSS 持久化 | `Sources/LegadoCore/Persistence/RSSRepository.swift`、`Sources/LegadoCore/Persistence/LegadoDatabase.swift` |

主要数据流：

1. 文件、文本、URL 或深链接进入 `RSSLibraryModel`，由 `RSSSourceImporter` 解码和合并，再通过 repository 保存。
2. `RSSSortResolver` 解析分类；`RSSService` 复用请求构建和网络策略获取列表或正文。
3. `RSSRuleParser` 在没有列表规则时使用 `RSSDefaultParser`；自定义规则通过通用 `RuleEngine` 执行。
4. 页面模型维护文章、分页、阅读状态和收藏；`RSSReadingPolicy` 决定 HTML、网页、图片或视频模式，UI 承接展示和交互。

## Android 对照入口

以下路径相对于 Android 基准的 `app/src/main/java/io/legado/app/`：

| 兼容主题 | Android 文件 |
| --- | --- |
| RSS 字段与默认值 | `data/entities/RssSource.kt`、`data/entities/RssArticle.kt` |
| 导入格式、源校验 | `ui/association/RssSourceImport.kt`、`ui/association/ImportRssSourceViewModel.kt` |
| 分类规则 | `help/source/RssSourceExtensions.kt` |
| 请求、列表、正文和分页 | `model/rss/Rss.kt`、`model/rss/RssParserByRule.kt`、`model/rss/RssParserDefault.kt` |
| 规则上下文与请求语义 | `model/analyzeRule/AnalyzeRule.kt`、`model/analyzeRule/AnalyzeUrl.kt` |
| 通用 JS、URL、缓存 | `help/JsExtensions.kt`、`utils/JsURL.kt`、`help/CacheManager.kt` |
| 网页桥接与正文展示 | `help/webView/WebJsExtensions.kt`、`ui/rss/read/RssJsExtensions.kt`、`ui/rss/read/ReadRssActivity.kt`、`ui/rss/read/ReadRssViewModel.kt` |

对照具体 API 时核实参数顺序、重载、返回类型、链式调用、`null` 与空字符串语义、URL 基准和变量作用域，不能只补同名方法。规则 JS 与页面 JS 是不同运行上下文，两边都要检查。

RSS 验收至少涵盖导入与持久化、分类和源内搜索、列表解析与分页、正文及交互、收藏与重启恢复。按实际源用到的能力补充 Header、Cookie、登录、JavaScript、图片和视频验证。

初始化时发现的后续核对项（不代表已经修复或完成全面审查）：Android 源模型已有 `nextContentUrl` 和 `enableReadRecord`，当前 iOS `RssSource` 未声明这两个字段。成功解码或普通 RSS XML 测试通过，不能证明这些行为兼容。

修改网页桥接时保留已有边界：远程 `.web` 页面不获得原生桥接；可桥接模式仍须配置非空 `preloadJs`；主框架来源检查和外部导航确认不得因兼容修复失效。

## 验证方法

先识别当前操作系统和工具链。本机初始化环境为 Windows / PowerShell，没有 `swift` 和 `xcodebuild`；iOS 构建与 UI 测试需要 macOS/Xcode 或 GitHub Actions。不得把 Windows 静态检查、Python 检查或历史 CI 结果表述为当前 Swift/iOS 测试通过。

macOS 上的针对性回归命令：

```sh
swift test --disable-sandbox --filter RSSRegressionTests
swift test --disable-sandbox --filter RSSLibraryRegressionTests
swift test --disable-sandbox --filter JavaScriptRuleEvaluatorTests
```

按改动范围执行完整包测试和 App 模拟器构建；完整自检入口为 `sh scripts/self-check.sh`，详细参数见开发指南。

```sh
swift test --disable-sandbox
xcodebuild -project Legado.xcodeproj -scheme Legado -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

RSS UI 回归使用 `LegadoRSSFlowUITests` Scheme，其中包含入口与默认首页、Files 导入、搜索分页及阅读收藏三个测试。测试代码位于 `Tests/LegadoReaderUITests/RuleEditorUITests.swift`。

1. 在 macOS 启动测试模拟器。
2. 在单独终端运行 `python3 scripts/fixtures/rss-flow-server.py`，服务地址为 `127.0.0.1:18763`。
3. 运行 `sh scripts/prepare-source-import-fixture.sh <模拟器UUID>` 安装独立夹具应用；UI 用例会生成并存储样本。
4. 运行 `xcodebuild -project Legado.xcodeproj -scheme LegadoRSSFlowUITests -destination 'platform=iOS Simulator,id=<模拟器UUID>' CODE_SIGNING_ALLOWED=NO test`。

文件导入 UI 用例会启动独立夹具应用，通过系统导出选择器将 7 个样本存到 Files，再走正式 App 的导入选择器。不要从宿主机直接写 Files 容器，也不要修改提供器数据库。Files 的历史失败与验证记录见 `docs/DEVELOPMENT.md`。

- `.github/workflows/build-ios.yml` 提供 `build/test/ipa`：手动默认仅编译；源码推送运行核心、RSS UI 与网页桥回归；仅手动 `ipa` 在回归通过后 Archive 和生成未签名 IPA。网页桥在 UI 失败后仍执行，整体失败状态保留。
- `.github/workflows/rss-live-smoke.yml` 运行公开 feed 的网络检查。`scripts/check-public-rss-feeds.py` 只验证端点和 feed 数据，不能替代 Swift 规则执行及 iOS 使用链路。
- `Tests/LegadoCoreTests/Fixtures/RealWorldRSS/` 中 XML 是合成样本，不是完整真实源集合；保持回归确定性，不依赖第三方网站作为唯一测试依据。
- 功能和兼容修复优先补能触发真实问题的最小回归；文档和低风险文案修改无需机械添加测试。

## CI 与交付

- 诊断 CI 先对齐 PR 的 `headRefOid` 和运行的 `headSha`，检查第一个实际失败步骤及完整错误，区分编译失败、断言失败和运行环境问题。
- 初始化时 `76f8bce` 对应运行 [42202887561](https://github.com/DenisZheng/legado-ios/actions/runs/42202887561)：包测试通过，RSS 文件选择导入 UI 测试在等待导入源出现时失败，Archive / IPA 步骤被跳过。此处是历史排查起点，后续状态以新运行结果为准。
- 不通过跳过失败测试、删除断言、吞掉退出码或无依据延长超时来制造通过结果。
- 修复后验证实际修复提交，交付说明写清根因、行为变化、运行的测试和未验证范围；PR 描述遵循 `.github/pull_request_template.md`，不能沿用过期的成功结论。
- 未经用户要求不合并 PR、不发布 Release。签名、证书和发布产物不进入源码提交。

## 工具与数据约定

- 查找文件或文本优先 `rg --files` / `rg`。命令使用当前系统的原生语法，不混用 PowerShell 与 POSIX shell。
- 长输出用当前平台工具分段读取，完整保留构建错误、测试失败、堆栈和 diff；不要截掉关键失败信息。
- 纯本地改动无需网络搜索；SDK/API/框架/CLI/云服务文档优先 Context7，其次官方来源。版本、公告、漏洞、价格和政策等时效信息必须实时核实，工具不可用时说明不确定性。
- 使用临时数据库和合成响应测试，避免操作个人书架。公开夹具、日志和截图不得包含账号、Cookie、Token、私有源或完整付费正文。
- 临时 CI 日志和诊断产物放在已忽略的 `artifacts/` 下，不把构建缓存、`.xcresult`、IPA 或签名文件加入提交。
- 根目录 `rssSources-valid (1).json` 是用户提供的 307 源集合，已精确忽略，不上传。换 Mac 时单独复制；接续步骤与未完成项见 `docs/MAC_HANDOFF.md`。
- 遵守 GPL v3，保留第三方版权与许可；相关信息见 `THIRD_PARTY_NOTICES.md`。

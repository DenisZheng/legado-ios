# RSS 兼容任务与实施计划

## 目标与对照版本

让 Android Legado RSS 源在 iOS 完成导入、分类/搜索、刷新、文章解析、正文展示和媒体使用。按 P0 → P1 → P2 推进产品能力，P3 验证从第一批开始持续执行。

- 盘点日期：2026-11-06。
- iOS 起点：`feature/rss-navigation-compat`，`10afd1e8fcebdf88a41fa251a2af1f8d4bf984fa`。
- Android 基准：本机 `E:\Projects\legado`，`330e606c4d57e08adc056ff8ab7a4132c784da9a`，只读对照。
- 本计划依据该提交的实际代码；基准不是对所有 Android 版本的承诺。
- 后续已收到根目录 `rssSources-valid (1).json`，本地核实为 307 条、307 个唯一 `sourceUrl`。已生成清单与逐阶段空矩阵，尚未执行真实源链路；静态盘点结果见 [测试矩阵的集合记录](RSS_COMPATIBILITY_MATRIX.md#307-源集合盘点)。原先 API 使用次数是需求背景，新统计为字面引用数，不代表动态执行次数。
- 实现状态与验证状态分开记录：有同名函数不等于参数、返回类型、异常、线程和生命周期兼容。
- 验证方法、代表场景和逐源记录格式见 [RSS_COMPATIBILITY_MATRIX.md](RSS_COMPATIBILITY_MATRIX.md)。

## 当前结论

| 方向 | 已有基础 | 尚未完成 |
| --- | --- | --- |
| P0 规则兼容 | 常用 JS/DOM、URL 模板、动态 Header、Cookie 请求、顶层 WebView 请求、部分页面桥 | 契约差异、登录链路、页面 Cookie 同步、子资源补头、交互式 JS API |
| P1 原生视频 | WebKit `<video>`；文章级收藏和历史 | RSS AVPlayer/AVKit 模块、媒体请求策略、续播、方向/倍速/手势、MPD 评估 |
| P2 图文体验 | 单图查看、带头下载、保存相册、HTML 展示 | 缩放/连续浏览、懒加载、正文分页、位置保存恢复 |
| P3 验证 | 两个公开 feed 检查、合成 XML、规则回归、RSS UI；已收到 307 源并建立静态清单 | 逐阶段实际执行、登录/图片/视频真机覆盖 |

## Android 行为依据

以下 Android 路径相对于 `app/src/main/java/io/legado/app/`。iOS 路径相对于本仓库。

| 主题 | Android 入口与已确认行为 | iOS 对应位置 |
| --- | --- | --- |
| 分析器 | `model/analyzeRule/AnalyzeRule.kt:104`：`setContent`/`setBaseUrl` 可链式调用；`:125`：`setRedirectUrl` 保存独立重定向地址，data URL/无效地址保留旧值，返回 URL 或 null；提取链接使用重定向地址 | `Sources/LegadoCore/RuleEngine/JavaScriptRuleEvaluator.swift` |
| URL 对象 | `utils/JsURL.kt`：提供 `host/origin/pathname/searchParams`；不是修改参数就重写地址的浏览器 URL 对象 | 同上 `java.toURL` |
| 缓存 | `help/CacheManager.kt`：`saveTime` 单位秒，0 为不限时；有期限的持久条目不放入无期限内存缓存；`onlyDisk` 不走内存 | `Sources/LegadoCore/RuleEngine/JavaScriptRuleCache.swift` |
| 源自定义变量 | `data/entities/BaseSource.kt:331`：`setVariable`/`putVariable` 保存整段字符串，null 删除；`:356`：无参 `getVariable` 读取，缺省为空字符串；存储与 `get(key)/put(key,value)` 独立 | `JavaScriptRuleEvaluator.installSource` 当前缺少这组接口；真实集合有大量引用 |
| HTTP JS | `help/JsExtensions.kt:575`：`get/head/post` 返回 Jsoup Response、不自动跟随重定向；页面 `help/webView/WebJsExtensions.kt:193` 接收 JSON Header 字符串，get/post 返回正文、head 返回 JSON 字符串 | 规则引擎及 `App/Features/RSS/RSSWebReaderView.swift`，两种上下文分别核对 |
| 人工验证 | `help/JsExtensions.kt:399`：`startBrowser` 打开页面；`startBrowserAwait` 等待响应或重取；`getVerificationCode` 等待用户输入 | 当前仅有浏览器原生路由，尚无对应规则 API |
| RSS 请求登录检查 | `model/rss/Rss.kt`：列表和正文请求完成后执行 `loginCheckJs`，失败响应也可进入检查，结果为响应对象 | `Sources/LegadoCore/RSS/RSSService.swift`；需要继续核对与网页登录检查的差别 |
| 子资源代理 | `ui/rss/read/RssWebResourceProxy.kt`：识别媒体、Range、GET/HEAD，合并请求头/当前 Cookie；调用处受 Cronet 配置限制 | RSS 阅读页没有对应补头通道；不能照搬 Android 拦截 API |
| 正文分页 | `model/rss/Rss.kt:getContentAwait/analyzeContentPage`：`nextContentUrl`；单链接逐页跟随并去环，多链接获取后拼正文；仅正文类型启用 | `RSSModels.swift`、`RSSService.swift` 尚无正文分页链路 |
| 视频 | `ui/rss/read/ReadRss.kt` → `model/VideoPlay.kt:165`：RSS type=2 走独立播放器，规则返回 URL 或 MPD 文本；请求经过 AnalyzeUrl，播放使用 Header，`durPos` 保存播放时间 | 当前 `RSSWebReaderView` 输出 HTML `<video>` |
| 图片 | `ui/widget/dialog/PhotoDialog.kt`、`ui/widget/image/PhotoView.kt`：带来源加载、单图缩放拖动；RSS 保存图片在 `ReadRssViewModel.kt` | `App/Features/RSS/RSSViews.swift:RSSPhotoView` |
| 历史 | `ReadRss.kt:49` 检查全局 `AppConfig.enableRssReadRecord`；`RssSource.kt` 声明 `enableReadRecord`，当前入口未消费该字段 | `RSSLibraryModel.read` 直接写记录；源字段与全局设置分别核对 |

连续图片浏览和 HTML 懒加载作为本项目体验目标推进；本次没有确认它们是 Android 上述单图入口的既有行为。`durPos` 有字段不证明 HTML 阅读位置已经恢复。

## P0 任务清单

状态是计划建立时的代码快照；后续完成记录在文末执行表，避免用新状态覆盖对照依据。

| ID | 任务与当前状态 | 实施范围 | 验收条件 |
| --- | --- | --- | --- |
| P0-01 | cache 基础已有，TTL 有明确差异 | 修复持久条目读取后丢失期限；保留 `onlyDisk` 和显式 `putMemory` 语义 | 限时条目过期后不再返回旧值；不限时可走内存；覆盖写入和跨次 JS 求值有回归 |
| P0-02 | 分析器部分兼容；规则侧缺 `setRedirectUrl` | 对齐参数、链式返回、URL/null、基准地址与重定向地址的区别；页面侧同步核查 | 链接按重定向地址解析；空正文返回/无效地址行为对齐；不改变既有变量和结果快照 |
| P0-03 | HTTP 重载、页面网络桥已接通，返回契约待完善 | 区分规则 Response 与页面字符串；Header 支持对象/JSON；超时、错误、禁重定向、JS 状态连续性 | 同一合成请求在两个上下文分别得到基准规定的类型、头、状态和正文；错误不会伪装为正常正文 |
| P0-04 | 静态/动态 Header、URL/bodyJs 已有 | 补登录页动态 Header 路径；对照合并优先级、charset、POST/bodyJs、变量及最终地址 | 请求捕获断言方法、字节和 Header；重定向/编码组合有确定回归；`webViewDelayTime` 正确生效 |
| P0-05 | 请求 Cookie 已有；阅读页同步不完整 | 复用 LegadoCookieStore；显式同步 WKHTTPCookieStore；覆盖删除、更新、跳转与启用开关 | 登录后规则与页面均可用；页面更新/退出登录可回写；并发源不串 Cookie；第三方 Cookie 另记真机结果 |
| P0-06 | 网页登录入口已有；RSS `loginUi` 表单未实现 | 对照 JSON/JS 表单、登录信息和 Header 持久化；明确规则请求 `loginCheckJs` 响应契约 | 表单读写、取消、登录失败/成功及请求重取均可复现；网页检查与请求检查不混用 |
| P0-07 | 顶层 `webView:true` 已有，函数式接口缺失 | `java.webView/webViewGetSource/webViewGetOverrideUrl`；复用现有执行器，补参数和结果传递 | 页面完成、匹配跳转、超时、取消均返回明确结果；同步 JS 不阻塞主线程 |
| P0-08 | 页面桥已有子集 | 补页面 Cookie 缺失项和实际源使用的网络/缓存/文件桥；核对 inject/preload/startHTML 路径 | 特权桥仅在现有允许范围运行；多次调用变量与 source 状态一致；远程页面回归仍通过 |
| P0-09 | 媒体子资源补头缺失 | 明确主文档、图片、视频/音频、Range、重定向的请求职责；先验证 WebKit 可行路径再实施 | 防盗链图片和媒体成功；206/Range 不损坏；目标域 Cookie 正确；资源释放和取消正常 |
| P0-10 | 加密工厂已有 AES-CBC 子集 | 先从源集合提取实际 transformation/charset/输入类型，再补对应算法与重载 | 使用 Android 对照向量，验证密文/明文与错误；不以一次往返加解密证明兼容 |
| P0-11 | 浏览器路由已有，脚本人工验证缺失 | `startBrowser/startBrowserAwait/getVerificationCode`；人工操作、等待/取消/超时、Cookie 回填 | 一次规则调用能打开 UI、完成操作后继续；取消不写入假成功；并发调用不弹重复页面 |
| P0-12 | 文件/脚本/压缩 API 缺失 | `importScript/downloadFile/cacheFile/getFile/readTxtFile/deleteFile` 及 zip/rar/7z；按实际源需求逐个评估 | 编码、返回路径、缺失文件、范围与容量限制明确；既有附件下载不能替代 API 验收 |
| P0-13 | 低频工具 API 缺失 | `t2s/s2t/htmlFormat/toNumChapter/getThemeConfig/getReadBookConfig/lock/singleFlight/tick/queryTTF/replaceFont` | 按真实调用建立样例；未支持项列明，字体解析和新依赖先给成本依据 |
| P0-14 | 页面部分路由已有 | 补需要的 `java.open` 分支、方向锁定、关闭回调，与原生视频全屏协调 | 返回/关闭恢复页面状态和原方向；不绕过现有外部导航确认 |
| P0-15 | 源字段尚有遗漏 | 核对 `nextContentUrl/enableReadRecord` 等导入、编辑、导出、持久化字段 | 不因导入成功就丢字段；分页随 P2-03 接通；历史字段行为先明确基准和产品设置 |
| P0-16 | 源自定义变量 API 缺失，新集合确认高频 | 对齐 `source.getVariable()/setVariable()/putVariable()`，与已有键值 get/put 分开；核对页面侧使用范围 | 缺省、设置、null 清除、跨求值/重启、不同源隔离；动态分类与登录后重算使用相同变量；不简单别名到带参数的 get/put |

`longToast`、`toURL`、常用 get/put/DOM、JavaImporter 白名单等保留已有实现，按矩阵扩展回归，不再安排重复开发。规则 `longToast` 当前只是诊断日志；文件缓存、任意 Java 类和全套 Cipher 仍不能宣称已兼容。

## P1 原生视频任务

沿用现有 RSS 路由、来源信息、收藏和记录 repository，使用 AVPlayer/AVKit 建立独立模块。与 TTS AVPlayer 分离，先不新增第三方播放器依赖。

| ID | 任务 | 依赖与验收 |
| --- | --- | --- |
| P1-01 | 解析播放输入并建立 AVPlayer/AVKit 生命周期 | 区分 URL、带 URL 选项的值、MPD 文本；错误可见；文章切换、关闭、前后台不遗留播放/观察者 |
| P1-02 | HLS/M3U8 与 HTTP Header/Cookie | 依赖 P0-04/05/09；MP4、主/子 playlist、分片、key、跨域和 206 分别验证；原始请求成功不能代表后续请求成功 |
| P1-03 | 全屏、横竖屏 | iOS 15 与较新系统各自验证；iPad/分屏、退出全屏、返回列表恢复状态；与 P0-14 协同 |
| P1-04 | 播放进度记忆 | 以来源+文章标识关联，明确毫秒单位；节流保存、退出保存、从收藏/历史恢复；直播和失效时长单独处理 |
| P1-05 | 倍速、手势控制 | 先倍速/拖动定位，再亮度/音量/快进手势；处理手势冲突、无障碍和播放失败 |
| P1-06 | MPD 支持评估 | 包含 MPD URL 与原始 XML；记录 AVFoundation 实测结果、替代方案/包体/许可/维护成本；本阶段不承诺支持，不暗中加播放器或服务端转码 |
| P1-07 | 视频收藏与历史完整接入 | 复用已有文章级收藏，补播放进度和恢复；删除源、重启、签名 URL 过期后重解析均有验证 |

媒体请求实现先做小范围技术验证。Apple 的 resource loader 在资源需要其协助时工作，不能据此假设它能拦截所有普通 HTTP HLS 请求；WebKit 自定义 scheme 也不能直接等同 Android 的 `shouldInterceptRequest`。不使用未经确认的私有 Header 选项作为完成依据。

## P2 图文任务

| ID | 任务与状态 | 验收 |
| --- | --- | --- |
| P2-01 | 单图查看已有，补捏合/双击缩放和连续浏览 | 放大拖动、还原、长图和旋转不丢位置；正文图片列表顺序明确，点击打开对应项；失败项可继续浏览 |
| P2-02 | HTML 图片懒加载未实现 | 处理已有 src/srcset 和动态内容；首屏正常、滚动加载；不得覆盖源自己的懒加载脚本；与阅读位置恢复协同 |
| P2-03 | 正文分页未实现 | 依赖 P0-02/04/15；单下一页/多页链接、去环/去重、重定向、页序、取消和失败处理；不能混同列表 `ruleNextPage` |
| P2-04 | 图片保存已有 | 保留 Header/Cookie 下载和相册写入；补 data URL、失败/拒绝权限、不同图片格式的实测记录 |
| P2-05 | `durPos` 已存储，HTML 位置恢复未接通 | 采集/节流保存、退出/重启恢复；图片延迟加载、分页追加、字号/横竖屏改变后校正；明确与视频毫秒进度的区别 |

## P3 验证任务

| ID | 任务 | 交付物 |
| --- | --- | --- |
| P3-01 | 建立能力场景及记录规范 | [测试矩阵](RSS_COMPATIBILITY_MATRIX.md)，每项映射任务 ID、用例和证据级别 |
| P3-02 | 定位用户源集合并建立清单 | 本地导出指纹、去重规则、实际数量、能力标签、Android 实测版本；原始私有数据留在忽略目录 |
| P3-03 | 代表源第一轮逐阶段验证 | 每类至少一个源；导入/刷新/列表/正文/图片/视频分别给结果；失败缩减成可公开的合成用例 |
| P3-04 | 全集合回归与版本差异 | 固定集合、设备/网络和提交；比对修复前后，区分网站失效、需登录、iOS 缺陷、未支持和未测 |
| P3-05 | 自动化与 CI | 保留确定性核心/UI 回归；真实源联网运行显式触发；各阶段记录独立，失败不能被下游跳过掩盖 |

## 执行顺序和完成门槛

不估算没有样本支持的完成百分比或日程。每批保持可独立审阅、回退和验证，完成后更新下表；较大批次按任务 ID 拆提交。

| 批次 | 范围 | 依赖 | 本批交付与停止扩展条件 |
| --- | --- | --- | --- |
| M0 | 本文、P3-01 | 基准代码核对 | 任务、状态、依据和验收可追溯；文档先落地，再修改功能 |
| M1 | P0-01 缓存期限回归与修复 | M0 | 确认 Android TTL 契约、补最小回归、验证实际修复提交；不扩展为缓存重构 |
| M2 | 先 P0-16，再 P0-02/03/04；P3-03 开始 | M1；307 源清单现已提供 | 优先修复实际集合高频的源自定义变量，再验证分析器/HTTP/编码契约；补独立页面桥集成运行，不能以包测试替代 WKWebView |
| M3 | P0-05/06/08/09 | M2 | 登录、Cookie、页面网络及资源补头形成可用链路；媒体方案先完成公开 API 技术验证 |
| M4 | P0-07/10/11/14，P0-12/13 按源用量 | M2/M3 | 函数式 WebView、人工验证、实际用到的加密/工具；单个高成本 API 不阻塞已支持源验收 |
| M5 | P1-01～07 | M3 媒体请求策略；P0-14 | 原生视频基础 → 请求/全屏 → 续播/交互；MPD 单独给评估结论 |
| M6 | P0-15、P2-01～05 | M2/M3；图片位置依赖稳定内容加载 | 分页 → 图集/懒加载 → 位置恢复；图片保存补实测 |
| 持续 | P3-03～05 | 每批实现 | 新失败归入任务 ID，回归通过后更新逐源结果；P0 未完也可先做代表源验证 |

所有功能任务的完成门槛：基准行为有依据、最小回归能触发问题、修复后的对应测试通过、App 受影响时完成构建、真实源/真机未测项明确记录。记录“未测/不支持/需人工操作”，不把它们统计成通过。

本机为 Windows，无 Swift/Xcode。Swift 与 iOS 测试通过 macOS/GitHub Actions 获取；Windows 文档检查不能替代测试。当前 CI 会运行包测试及 RSS UI Scheme，**不会自动运行 `LegadoReaderTests` 中全部网页桥集成测试**。

## 执行记录

| 批次 | 状态 | 记录 |
| --- | --- | --- |
| M0 | 已完成文档 | 固定两个仓库的起点，建立任务与测试矩阵 |
| M1 | 已实施，验收以修复提交 CI 为准 | 新增 5 项缓存回归及 1 项跨 JS 求值回归；旧实现 `a474da6` 在 [42211370651](https://github.com/DenisZheng/legado-ios/actions/runs/42211370651) 出现 3 项预期失败、4 个断言问题；随后修复限时条目进入永久内存缓存的问题，并补并发读写回归 |
| M2～M6 | 未开始本轮实施 | 已有功能见快照表；不会将此前实现重复算为本轮交付 |
| P3-02 | 本地清单已建立 | `rssSources-valid (1).json`：307 条且无重复；固定文件指纹并生成 2456 条逐阶段记录；Android/iOS 实际执行仍未进行 |
| P3-03/04 | 待执行 | 逐源记录当前全部为 `NOT_RUN`；不能以 JSON 结构有效或静态引用统计替代真实规则执行 |

M1 使用可注入时钟和独立 UserDefaults 测试存储，覆盖到期前读回/到期后失效、限时覆盖、显式内存覆盖、onlyDisk、不限时重写和两次 JS 求值。修复调整内存提升条件，并把同一缓存实例的持久文本/内存读写放进同一临界区，避免并发读到新值与旧期限的组合。不扩展缓存 API 或改变生产存储格式。最终验证应查询本分支对应修复提交的 [Build iOS IPA](https://github.com/DenisZheng/legado-ios/actions/workflows/build-ios.yml)。

缓存范围边界：本批回归覆盖 `saveTime = 0` 和正整数秒。负数目前在 JS 桥中被归零，而 Android 文本缓存会计算已过去的 deadline；这一差异仍归 P0-01 后续，不因修复永久内存提升问题就宣称全套 cache 参数契约一致。文件缓存和非文本值也需按实际源调用继续核对。

集合定位补充：最初只找到 Android `app/src/main/assets/defaultData/rssSources.json` 的 4 条内置源；用户随后提供完整 307 源。原文件保留根目录，通过本地 `.git/info/exclude` 排除，当前清单与结果放在已忽略的 `artifacts/rss-compat/20261106-inventory-v2/`，初版清单也保留。第二版修正 `source.*` 和 JS 字段的能力标签，避免将只用源变量的规则误选为无 JS 对照组。

M1 验证补充：`1555ea3` 的 [运行 42212284372](https://github.com/DenisZheng/legado-ios/actions/runs/42212284372) 中 391 项核心测试通过；RSS UI 有 1 项失败，另 2 项通过。失败发生在 Files 冷启动后未点击 Browse 就查找 On My iPhone，尚未选中文件。随后修正该测试的就绪状态等待与目录导航，保留最终导入断言；完整 CI 仍须验证后续修复提交。

`3db20c6` 的 [运行 42214902416](https://github.com/DenisZheng/legado-ios/actions/runs/42214902416) 已通过导航，但在 Open 后复现系统文件 ID 无法解析（`NSFileProviderErrorDomain -1005`），返回空文件列表。后续 CI 改为相同机型/runtime 的全新专用模拟器，隔离预置设备的文件索引状态，继续运行原有导入断言。该环境问题与缓存回归分别记录，不能把一次绿色运行当成根因证明。

本地文件链路补充：对照现有书源实现后，RSS 改为复用 `SourceFileImportPicker` 和 `SourceImportFile`：选择 `.item` 副本、回调时持有访问权限、通过 `NSFileCoordinator` 后台读取；文件返回和 sheet 关闭都完成后才启动导入。RSS 保留自身 JSON 解码、错误文案和持久化逻辑。原先仅凭 `asCopy: true` 就直接异步读取 URL 的实现未覆盖书源已有的完整时序。新增多文件/混合扩展名和失败不部分入库回归，RSS UI 增加取消后重开；RSS CI Scheme 同时加入现有书源 JSON 文件导入用例，以验证共享组件。此变更须由后续提交的 CI 验证，不能引用旧运行证明。

`ce9e857` 的 [运行 42219274584](https://github.com/DenisZheng/legado-ios/actions/runs/42219274584) 通过 393 项核心回归，4 项 UI 中 2 项通过、2 项失败。书源丢失第二个文件，RSS 返回空文件列表，系统均记录文件 ID 不存在。该次全新模拟器实际为 iOS 26.4，不能认为仅换新设备已解决问题。`4edf2b9` 固定 iOS 26.2，并将样本放到 Files 自身的 `Legado Import Fixtures` 目录，通过原选择器和导入断言继续验证，结果以 [运行 42224416883](https://github.com/DenisZheng/legado-ios/actions/runs/42224416883) 为准。

## 平台资料

2026-11-06 经 Context7 查询 Apple Developer Documentation，选择 `/websites/developer_apple_de`（Apple 官方文档镜像索引）。以下仅支持设计约束，不代表已完成设备实验：

- [WKWebsiteDataStore.httpCookieStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/httpcookiestore)：WKWebView 的 Cookie 管理入口，需显式同步。
- [UIDocumentPickerViewController](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)：外部文档需协调读取与成对的 security-scoped 访问；本地副本不一定需要额外授权，共用读取对象仅在取得授权时释放，不能将 `startAccessingSecurityScopedResource() == false` 一律视为副本不可读。
- [WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)：处理 WebKit 不原生处理的 scheme。
- [AVAssetResourceLoadingRequest](https://developer.apple.com/documentation/avfoundation/avassetresourceloadingrequest)：资源加载协助和完成/失败回调。
- [使用 AVFoundation 播放和保存 HLS](https://developer.apple.com/documentation/avfoundation/using-avfoundation-to-play-and-persist-http-live-streams)：HLS 能力参考；具体 Header/Cookie 路径仍需实测。

新增 API 按 iOS 15 最低版本核实可用性，不能直接照搬文档的新系统示例。

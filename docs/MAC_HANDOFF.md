# Mac 开发接续

## 仓库与入口

```sh
git clone --branch feature/rss-navigation-compat https://github.com/DenisZheng/legado-ios.git
cd legado-ios
git status --short
open Legado.xcodeproj
```

已克隆时先确认没有未提交修改，再运行 `git switch feature/rss-navigation-compat` 和 `git pull --ff-only`。工作在该分支，草稿 PR 为 [#1](https://github.com/DenisZheng/legado-ios/pull/1)，目标是 Fork 的 `main`；尚未合并或发布。

先读根目录 `AGENTS.md`、[开发指南](DEVELOPMENT.md)、[RSS 计划](RSS_COMPATIBILITY_PLAN.md) 和 [验证矩阵](RSS_COMPATIBILITY_MATRIX.md)。本文件供换机接续，测试结果以对应提交的 CI 及计划执行记录为准。

需要完整 Xcode、Python 3；`gh` 用于查询或触发 CI，`rg` 用于检索。首次打开工程等待 Swift Package 依赖解析完成。App Scheme 为 `Legado`；模拟器构建无需个人签名，真机运行需要在本机配置 Team。

## Android 基准与私人测试数据

Windows 的 Android 对照仓库为 `E:\Projects\legado`，远端 `https://github.com/LegadoTeam/legado.git`，固定提交 `330e606c4d57e08adc056ff8ab7a4132c784da9a`。在 Mac 上可把该仓库放到 iOS 仓库旁边，checkout 相同提交后只读对照；不要把 Windows 绝对路径作为 Mac 命令使用。

根目录 `rssSources-valid (1).json` 需要从 Windows 单独复制到 Mac。Git 精确忽略该文件；307 条源、日志、源身份映射和本地测试产物不会随 `git clone` 获取。文件应为 1,674,112 字节，核对命令：

```sh
shasum -a 256 'rssSources-valid (1).json'
```

期望 SHA-256：`0e30301c85fb511961be7542212ee63b8d4173a9b6c33bb5a4f88eb6d3795f45`。

Windows 本机另已准备 `artifacts/handoff/legado-ios-mac-private-fixtures.zip`，包含该源 JSON 和第二版清单的 3 个文件，ZIP 完整性及源文件摘要均已核对。可以把这个包单独复制到 Mac 后，在仓库根目录解压；此包不包含源码，也不会上传到 GitHub。

静态清单可重建到一个尚不存在的输出目录，或自行复制 Windows 的 `artifacts/rss-compat/20261106-inventory-v2/`：

```sh
python3 scripts/inventory-rss-sources.py 'rssSources-valid (1).json' \
  --output artifacts/rss-compat/mac-inventory \
  --ios-commit "$(git rev-parse HEAD)" \
  --android-commit 330e606c4d57e08adc056ff8ab7a4132c784da9a
```

该脚本不执行源 JS、不联网；2456 项阶段结果初始均为 `NOT_RUN`，不能把清单当成源可用性报告。

## 本地验证

日常先运行与修改相关的测试及增量编译，不需要每次生成 IPA：

```sh
swift test --disable-sandbox
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

UI 和网页桥需要启动具体模拟器。CI 使用 iPhone 17 Pro / iOS 26.2，工具链为 Xcode 26.6（17F113）；Mac 可以使用其他已安装 runtime，但记录版本，出现差异时优先对齐 CI。用 `xcrun simctl list devices available` 查询 UUID，将下例占位值替换后运行。模拟器可在 Xcode 的设备选择器中启动。

终端一：

```sh
python3 scripts/fixtures/rss-flow-server.py
```

终端二：

```sh
LEGADO_TEST_DEVICE='替换为已启动模拟器的 UUID'
sh scripts/prepare-source-import-fixture.sh "$LEGADO_TEST_DEVICE"
xcodebuild -project Legado.xcodeproj -scheme LegadoRSSFlowUITests \
  -destination "platform=iOS Simulator,id=$LEGADO_TEST_DEVICE" \
  -parallel-testing-enabled NO -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Legado.xcodeproj -scheme LegadoReaderTests \
  -destination "platform=iOS Simulator,id=$LEGADO_TEST_DEVICE" \
  -only-testing:LegadoReaderTests/WebReaderBridgeTests \
  -parallel-testing-enabled NO -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

UI 测试会通过独立应用的系统导出窗口保存一份带唯一目录名的夹具，再测试正式导入流程。测试使用演示数据；不要用个人书架作为测试环境。测试完成后关闭服务终端。Files 的历史故障发生在系统把文档 ID 转 URL 时，换 Mac 不等于自动消除此类故障，仍需按日志区分文件准备、系统回传和 App 解码阶段。

## 当前交付与下一批工作

换机停止点：最终代码为 `d55585c`。用户要求停止 Windows 侧验证，最后的 UI 验证交给 Mac；[CI 42235912502](https://github.com/DenisZheng/legado-ios/actions/runs/42235912502) 已在排队阶段取消。**Files 导入修复和 `WebReaderBridgeTests` 尚未完成最终验收。** 请在 Mac 优先执行上面的 4 项导入/RSS UI 与 3 项网页桥测试，再继续开发。

已知证据：`f7f5d3a` 的 397 项核心测试及仅编译通过；旧 Files 方案仍有 2 项导入 UI 失败。`773bd20` 的运行完成了新的系统导出和 7 个文件内容校验，随后被取消，尚未走完正式导入断言。`022d0aa` 再补协调读取，`d55585c` 统一 LF；不能把前一轮部分执行当成最终修复通过。本次没有生成新 IPA。

- P0-01：缓存期限丢失已修复并有回归；负期限、文件缓存及非文本契约仍待核对。
- P0-16：规则与 RSS 页面均已补齐 `source.getVariable/setVariable/putVariable`，与已有 `get/put` 键值存储隔离，共用持久缓存。新增空值、别名、多源、跨求值、持久化和动态分类测试，以及 WKWebView 双向读写测试。
- CI：`build` 仅编译；`test` 包含核心、4 项 RSS/书源 UI 和网页桥回归；`ipa` 才执行完整回归和 Release Archive。源码推送默认 `test`，手动默认 `build`。可在 Mac 本地完成 UI 调试；当前保留 CI 回归。
- 下一批按 M2 继续 P0-02/03/04：分析器返回与重定向契约、HTTP 重载/页面返回契约、Header 与 body/charset。先从 307 源挑代表用例，保留原始规则，逐阶段执行。
- P0 登录/Cookie/媒体子资源、函数式 WebView/人工验证等后续批次，P1 原生视频与 P2 图文完善尚未完成。307 源尚未逐条实测，不能保证任意源可用。

仅编译的已验证例子：[42229925320](https://github.com/DenisZheng/legado-ios/actions/runs/42229925320)，`f7f5d3a`，6 分 2 秒，不生成产物。旧 IPA [42224416883](https://github.com/DenisZheng/legado-ios/actions/runs/42224416883) 不包含新增的源变量 API；本轮按要求不再打包。

手动触发仅编译：

```sh
gh workflow run build-ios.yml --repo DenisZheng/legado-ios \
  --ref feature/rss-navigation-compat -f mode=build
```

将 `build` 换成 `test` 或 `ipa` 可运行对应模式。完整回归结果和 Files 修复证据记录在开发指南，不能用仅编译成功替代行为验证。

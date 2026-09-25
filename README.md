# Glance

**把截图变成下一步行动。** Glance 是一款 iOS/iPadOS 应用：选择一张截图，或从其他 App 的分享菜单发送图片，使用你配置的视觉 AI 模型获取摘要、搜索建议，以及可能相关的日历事件和提醒。你也可以圈选截图的一部分进行分析，并针对图片提问。

## 功能

- **导入截图**：从 Glance 的照片选择器选择截图，或通过系统分享菜单发送一张图片。
- **AI 分析**：生成简短摘要，并在合适时提供网页搜索建议、日历事件和提醒。
- **局部分析**：在截图上手绘圈选区域。发送给模型前，选区外的像素会被遮罩；分析结果与整图结果分开保存。
- **提问**：针对整张截图或选中的区域向 Glance 提问。
- **确认后执行**：搜索建议会打开所选搜索引擎；添加日历事件或提醒前需要由你确认。
- **本机历史记录**：查看、重新打开或删除已分析的截图及其分析结果。
- **自带 AI 服务**：支持兼容 OpenAI Chat Completions API、且具备图片理解能力的服务。API 密钥保存在系统 Keychain 中。

> Glance 不内置 AI 服务或 API 密钥。搜索建议会跳转到外部搜索引擎；提问功能本身不执行联网检索。模型能否正确识别截图内容取决于所配置的服务。

## 环境要求

- iOS/iPadOS 26 或更新版本
- 支持项目所用 SDK 的 Xcode
- 一个支持视觉输入的 OpenAI-compatible Chat Completions 服务及其 API 密钥

## 构建和运行

1. 克隆仓库并打开 `Glance.xcodeproj`。
2. 选择 `Glance` scheme，并在 Xcode 的 **Signing & Capabilities** 中为 `Glance` 和 `GlanceShare` 配置你的开发团队。
3. 在模拟器或设备上构建并运行 `Glance`。也可以在终端构建模拟器版本：

   ```sh
   xcodebuild -project Glance.xcodeproj \
     -scheme Glance \
     -destination 'generic/platform=iOS Simulator' \
     build
   ```

### 配置签名与共享容器

主 App 和 Share Extension 使用 App Group 共享服务配置、API Key 访问权限及历史记录。要使用自己的 Apple Developer Team 签名运行，需要在**两个 target** 上启用相同的 App Group 和 Keychain Sharing，并确保与代码中的标识符一致：

- App Group：`group.space.chenkai.glance`（`Shared/GlanceStorage.swift` 与两个 entitlements 文件）
- Keychain access group：`Shared/GlanceStorage.swift` 中的 `GlanceConstants.keychainAccessGroup`，以及两个 entitlements 文件中的 `keychain-access-groups`
- Bundle ID：默认分别为 `space.chenkai.glance` 和 `space.chenkai.glance.share`，可在 Xcode target 的构建设置中调整

这些标识符必须属于你的开发团队并在主 App、扩展及代码配置之间保持一致。使用自己的 App Group 或 Keychain access group 时，请一并更新上述位置，再重新签名构建。

## 配置 AI 服务

首次启动后，打开右上角的 **AI Provider** 设置，填写：

| 字段 | 说明 | 示例 |
| --- | --- | --- |
| Name | 服务名称，仅用于识别 | `OpenAI` |
| Base URL | OpenAI-compatible API 地址 | `https://api.openai.com/v1` |
| Model ID | 支持图片输入的模型 ID | `gpt-4o` |
| API Key | 服务提供方签发的密钥 | 由服务提供方提供 |
| Search engine | 搜索建议使用的搜索引擎 | Google、Bing 或 DuckDuckGo |

Glance 会向 Base URL 的 `/chat/completions` 端点发送请求；也可以直接填写包含该路径的完整端点。保存后可使用 **Test Connection** 测试配置。请确认服务商支持视觉输入和 OpenAI-compatible 图片消息格式。分析响应优先使用 JSON mode；若服务不支持该响应格式，Glance 会尝试不带 JSON mode 重试。

## 使用流程

1. 在 Glance 首页选择截图，或在其他 App 中打开系统分享菜单并选择 Glance。
2. 等待分析完成，查看摘要和可用操作建议。
3. 要聚焦细节时，点 **Draw area**，沿目标区域绘制闭合圈选，然后选择 **Analyze this area**。可撤销、清除选区，或在整图与已保存的局部分析之间切换。
4. 点 **Ask Glance** 对截图或当前分析区域提问。
5. 点搜索建议打开所选搜索引擎。添加日历事件或提醒时，按系统提示检查并确认；相关访问权限可在 **Permissions** 页面管理。
6. 首页的 **Recent** 和 **History** 可查看分析记录。删除历史记录会同时删除本地保存的截图文件。

## 隐私与数据

- 图片分析和提问会将对应图片发送至你配置的 AI 服务。请查看该服务提供方的隐私政策及数据处理条款。
- 整图分析会发送截图；局部分析和针对局部的提问会在发送前将选区以外的像素遮罩。
- API Key 存储于 iOS Keychain；服务配置、历史记录 JSON、图片及局部分析结果存储在 App Group 容器中，供 App 与扩展共享。项目本身没有自建云端存储或账号服务。
- 日历和提醒权限仅用于你确认添加对应操作时；Glance 不会在确认前创建事件或提醒。

## 项目结构

```text
Glance/             主 App 界面与历史记录
GlanceShare/        iOS 分享扩展
Shared/             分析界面、AI 接口、局部选区及共享存储
Glance.xcodeproj/   Xcode 项目和 Glance scheme
docs/               产品需求草案
```

`docs/screenshot-analysis-prd.md` 是截图分析功能的需求草案，其中也包含尚未实现的设想；请以当前应用中的实际功能为准。

# AnimeMaster Engine

<p align="center">
  <img src="assets/icon.png" alt="AnimeMaster" width="128" />
</p>

AnimeMaster Engine 是一个面向动漫追番、资料检索、资源缓存和本地播放的 Flutter 项目。它把 Bangumi 作品资料、收藏进度、RSS/磁力资源、本地缓存、播放器和弹幕体验放在同一个客户端里，目标是让用户从“发现一部番”到“看完一集”的路径尽量顺手。

这个仓库既包含可直接运行的 AnimeMaster 示例应用，也保留了 Flutter 插件层、Native FFI 代码、多平台工程和可选的 Bangumi OAuth 网关示例，适合继续开发成完整客户端，或作为动漫内容应用的工程基础。

## 你可以用它做什么

| 场景 | 体验 |
| --- | --- |
| 找番 | 浏览 Bangumi 新番放送、年度排行，通过关键词搜索作品 |
| 看资料 | 查看作品详情、角色、Staff、关联作品和短评 |
| 管收藏 | 登录 Bangumi 后同步收藏、查看进度、更新观看状态 |
| 找资源 | 通过 RSS/磁力源检索资源，并管理下载任务 |
| 做缓存 | 将下载内容沉淀到缓存中心，方便后续播放 |
| 看视频 | 使用内置播放器播放本地媒体，支持选集、倍速、全屏和弹幕 |
| 查更新 | 通过应用内更新清单发现新版 APK，并引导下载安装 |

## 核心功能

- **Bangumi 内容中心**：首页新番、排行、搜索、详情、角色、Staff、关联条目和收藏信息。
- **收藏与进度同步**：支持 Bangumi OAuth 登录，读取用户收藏并更新观看进度。
- **资源检索与下载**：内置 RSS/磁力检索、任务管理、缓存中心和基础资源解析能力。
- **本地播放体验**：基于 Flutter 播放页面整合选集、播放控制、亮度/音量、倍速、全屏等常用能力。
- **弹幕接入**：已接入弹弹play 的第一版弹幕链路，支持自动匹配和手动搜索剧集。
- **应用更新**：支持“检查更新 + 下载 APK”的侧载更新流程，适合个人分发或小范围测试。

## 适合谁

- 想要一个自用追番、资源管理和本地播放客户端的用户。
- 想基于 Flutter 开发动漫内容应用的开发者。
- 想研究 Bangumi API、移动端 OAuth、安全网关、FFI 与播放器整合的项目维护者。

## 当前状态

AnimeMaster Engine 仍处在持续迭代阶段，功能已经能串起主要使用流程，但不是一个完全打磨完成的商店级应用。

- Android 是当前最主要的运行和打包目标。
- 仓库包含 iOS、Windows 等平台工程，实际运行效果取决于本地 Flutter 与平台依赖环境。
- Bangumi 安全登录需要配合授权网关，客户端不会保存 `App Secret`。
- 弹弹play 弹幕需要用户自行申请并填写 `AppId / AppSecret`。
- 项目中仍有少量历史中文文案编码问题，后续可以继续清理。

## 快速体验

示例应用位于 `example/` 目录。第一次运行前请确保本机已经安装 Flutter、Dart、目标平台 SDK 和对应设备环境。

```powershell
git clone https://github.com/CongutSun/AnimeMaster_Engine.git
cd AnimeMaster_Engine\example
flutter pub get
flutter run
```

如果你有多个设备，可以先查看设备列表，再指定目标设备：

```powershell
flutter devices
flutter run -d <deviceId>
```

## 功能入口

| 页面/模块 | 说明 |
| --- | --- |
| 首页 | 展示新番放送、年度排行和内容入口 |
| 搜索 | 检索 Bangumi 条目并进入详情 |
| 详情页 | 查看作品信息、角色、Staff、关联作品和可用资源 |
| 收藏页 | 展示用户收藏与观看进度 |
| 下载中心 | 管理资源下载与缓存任务 |
| 播放器 | 播放本地视频，加载弹幕和常用播放控制 |
| 设置页 | 配置 Bangumi 登录、弹幕密钥、更新地址等应用选项 |

## 可选配置

普通体验不一定需要一次性配置所有服务。按你的使用场景逐步打开即可。

- **Bangumi 登录**：用于同步收藏、进度和用户信息。正式链路通过 HTTPS 授权网关完成，避免在客户端保存密钥。
- **弹弹play 弹幕**：在设置页填写弹弹play 的 `AppId` 和 `AppSecret` 后，播放器可以尝试自动匹配弹幕。
- **更新检查**：在设置页填写更新清单 URL 后，应用可以检查新版 APK 并跳转下载安装。
- **RSS/磁力源**：用于资源检索和下载任务管理，具体可用性取决于你配置的源和网络环境。

## 技术组成

- Flutter + Dart：主要界面、业务流程和跨平台应用层。
- Provider：应用设置、下载状态等轻量状态管理。
- Dio / html / dart_rss：网络请求、页面解析和 RSS 解析。
- media_kit：本地媒体播放能力。
- FFI + Native C/C++：保留底层原生扩展能力。
- Cloudflare Workers 或 Node.js：可选的 Bangumi OAuth 授权网关示例。

## 仓库结构

```text
lib/                         Flutter 业务代码与应用页面
src/                         Native FFI 代码
example/                     可运行、调试和打包的示例应用
example/RELEASE.md           Android 发版与更新清单说明
tools/bangumi_auth_worker/   Cloudflare Workers 版 Bangumi OAuth 网关
tools/bangumi_auth_gateway/  Node.js 版 Bangumi OAuth 网关
assets/                      应用图标等静态资源
release/                     更新清单示例
```

## 开发者入口

根目录用于插件和共享代码，实际应用运行入口在 `example/`。

```powershell
cd AnimeMaster_Engine
flutter pub get

cd example
flutter pub get
flutter analyze
```

构建 Android APK：

```powershell
cd example
flutter build apk --release
```

更完整的 Android 发版流程请看 `example/RELEASE.md`。Bangumi OAuth 网关代码位于 `tools/` 目录，适合维护者按自己的域名、Secret 和部署平台进行配置。

## 说明

AnimeMaster Engine 更偏向个人使用和持续演进中的客户端工程，而不是一个只需部署即可上线的服务端项目。README 的重点是帮助用户理解它能解决什么问题；具体网关部署、签名打包和更新分发可以在需要维护发布版本时再进入对应目录查看。

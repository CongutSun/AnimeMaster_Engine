# AnimeMaster Engine

AnimeMaster 是一个基于 Flutter 的动漫内容检索、收藏同步、缓存下载与本地播放项目。仓库同时包含：

- Flutter 插件与业务代码
- 可直接运行的示例应用
- Android 正式签名与打包脚本
- Bangumi 安全 OAuth 授权网关示例

## 主要功能

- 首页 Bangumi 新番放送与年度排行展示
- Bangumi 搜索、详情、角色、Staff、关联作品浏览
- Bangumi 收藏同步、进度更新、短评查看
- RSS 磁力检索、下载任务管理、缓存中心
- 本地播放器，支持选集、倍速、全屏、弹幕
- 弹弹play 第一版接入：自动匹配、手动搜索剧集、顶层滚动弹幕渲染
- 应用内检查更新与 APK 分发

## 目录说明

- `lib/`: Flutter 业务代码
- `src/`: Native FFI 代码
- `example/`: 真正用于安装、调试、打包的示例应用
- `tools/bangumi_auth_worker/`: Cloudflare Workers 版 Bangumi OAuth 网关
- `tools/bangumi_auth_gateway/`: Node.js 版 Bangumi OAuth 网关

## 环境要求

- Flutter 3.x
- Dart 3.x
- Android SDK
- JDK 17
- Node.js 18+，仅在部署 Bangumi 授权网关时需要

## 本地运行

示例应用不在仓库根目录启动，而是在 `example` 目录下启动。

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine\example
flutter pub get
flutter devices
flutter run -d <deviceId>
```

如果设备没有识别：

```powershell
adb kill-server
adb start-server
adb devices
flutter doctor
```

## 打包 APK

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine\example
flutter build apk --release
```

生成物路径：

```text
F:\AnimeMaster_Engine\AnimeMaster_Engine\example\build\app\outputs\flutter-apk\app-release.apk
```

覆盖安装：

```powershell
adb install -r F:\AnimeMaster_Engine\AnimeMaster_Engine\example\build\app\outputs\flutter-apk\app-release.apk
```

## Bangumi 安全登录

### 设计原则

客户端不再保存 `App Secret`。安全链路如下：

1. App 向授权网关请求登录入口
2. 网关生成 Bangumi 授权地址
3. App 打开系统浏览器进入 Bangumi 授权页
4. Bangumi 回调到你的 HTTPS 网关
5. 网关用 `client_id + client_secret + code` 换取 token
6. 网关保存 `refresh_token`
7. 网关把短期 `access_token` 和用户资料返回给 App
8. App 后续通过网关刷新 access token

### Flutter 端配置

正式版 App 已内置默认 Bangumi 授权网关地址，普通用户不需要填写网关信息。

App 自身的回调 Scheme 固定为：

```text
animemasteroauth://callback
```

这个 Scheme 由 App 用来接收网关最终跳回，不需要在 Bangumi 开发者后台登记。Bangumi 后台需要登记的是你自己的 HTTPS 网关回调地址。

### 推荐部署：Cloudflare Workers + KV

这是没有传统服务器时最省事的方案。Cloudflare 提供公网 HTTPS，Workers 运行授权逻辑，KV 保存 `state`、`session` 和 `refresh_token`。

Worker 版本位置：

```text
F:\AnimeMaster_Engine\AnimeMaster_Engine\tools\bangumi_auth_worker\worker.js
```

部署流程：

1. 安装 Wrangler：

```powershell
npm install -g wrangler
```

2. 登录 Cloudflare：

```powershell
wrangler login
```

3. 进入 Worker 目录：

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine\tools\bangumi_auth_worker
```

4. 复制配置模板：

```powershell
Copy-Item .\wrangler.toml.example .\wrangler.toml
```

5. 创建 KV Namespace：

```powershell
wrangler kv namespace create BANGUMI_AUTH_KV
```

把命令输出里的 `id` 填到 `wrangler.toml` 的 `id = "..."`。

6. 写入 Secret：

```powershell
wrangler secret put BANGUMI_CLIENT_ID
wrangler secret put BANGUMI_CLIENT_SECRET
```

7. 先部署一次，得到 Workers 域名：

```powershell
wrangler deploy
```

部署完成后会得到一个地址，例如：

```text
https://animemaster-bangumi-auth.<你的账号>.workers.dev
```

8. 设置 Bangumi 回调地址 Secret：

```powershell
wrangler secret put BANGUMI_CALLBACK_URL
```

输入内容应为：

```text
https://animemaster-bangumi-auth.<你的账号>.workers.dev/auth/bangumi/callback
```

9. 再部署一次：

```powershell
wrangler deploy
```

10. 打开 Bangumi 开发者后台，把 OAuth 回调地址设置为：

```text
https://animemaster-bangumi-auth.<你的账号>.workers.dev/auth/bangumi/callback
```

11. 如果你更换了 Worker 域名，请把新网关地址写入 `lib/src/config/embedded_credentials.dart` 的 `bangumiAuthGatewayUrl` 后重新打包。

12. 打开 App 设置页，点击“网页登录”。

### 备选部署：Node.js 网关

仓库内置了一个零依赖 Node.js 版本的最小网关：

```text
F:\AnimeMaster_Engine\AnimeMaster_Engine\tools\bangumi_auth_gateway\server.mjs
```

启动前需要配置环境变量：

- `BANGUMI_CLIENT_ID`
- `BANGUMI_CLIENT_SECRET`
- `BANGUMI_CALLBACK_URL`
- `PORT`，可选，默认 `8787`
- `APP_CALLBACK_SCHEME`，可选，默认 `animemasteroauth`

示例：

```powershell
$env:BANGUMI_CLIENT_ID="你的 Bangumi Client ID"
$env:BANGUMI_CLIENT_SECRET="你的 Bangumi Client Secret"
$env:BANGUMI_CALLBACK_URL="https://auth.example.com/auth/bangumi/callback"
$env:PORT="8787"
node F:\AnimeMaster_Engine\AnimeMaster_Engine\tools\bangumi_auth_gateway\server.mjs
```

网关提供的接口：

- `GET /health`
- `GET /auth/bangumi/mobile/start?callback_scheme=animemasteroauth`
- `GET /auth/bangumi/callback`
- `GET /auth/bangumi/mobile/session?session_id=...`
- `POST /auth/bangumi/mobile/refresh`
- `POST /auth/bangumi/mobile/logout`

### 部署建议

- 使用自己的域名和 HTTPS
- `BANGUMI_CALLBACK_URL` 必须与 Bangumi 开发者后台登记的回调地址完全一致
- 如果本地调试需要公网地址，可用反向代理或隧道工具把本地端口暴露出去
- `tools/bangumi_auth_gateway/data/store.json` 为运行时会话文件，已经加入忽略

## 弹弹play 弹幕

播放器已经实现第一版弹幕链路：

1. 优先按本地文件匹配节目
2. 匹配失败时允许手动搜索剧集
3. 选择目标剧集后拉取弹幕
4. 在播放器顶层滚动渲染

在应用设置页填写：

- `弹弹play AppId`
- `弹弹play AppSecret`

## 发布更新

更新不是静默推送，而是“检查更新 + 引导下载安装”。你需要：

1. 打包新的 APK
2. 上传 APK
3. 更新 `app_update.json`
4. 在应用设置页填写更新清单地址

可用脚本：

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine\example
.\tool\build_release.ps1
.\tool\write_update_manifest.ps1
```

## 常用开发命令

根目录分析：

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine
flutter pub get
```

示例应用分析：

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine\example
flutter analyze
```

## 当前注意事项

- Bangumi 安全登录依赖你自己部署的授权网关
- 弹弹play 仍需你申请自己的 `AppId / AppSecret`
- 播放器的弹幕匹配已经有手动兜底，但还没有做更复杂的本地缓存策略
- 项目里仍有部分历史中文文案编码问题，功能已可用，但源码文案还需要持续清理

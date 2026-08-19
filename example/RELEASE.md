# AnimeMaster Android Release

## 固定约束

- 不要修改 `applicationId`，否则旧版本无法覆盖安装。
- 不要更换 release keystore，否则旧版本无法继续升级安装。
- 每次发版前只递增 `example/pubspec.yaml` 里的 `version`。

## ⚠️ 覆盖安装、签名与 versionCode

当前 Gradle 配置会在一次标准 Release 构建中同时生成三个 ABI APK 和一个通用 APK，四个 APK 必须使用相同的 `versionCode` 和同一个正式签名。

发布前必须同时满足：

1. 新 `versionCode` 严格大于上一版所有 APK 的实际值。
2. 四个 APK 的 `versionCode` 完全一致。
3. 四个 APK 的签名 SHA-256 与上一版一致。
4. 不修改 `applicationId`。

`build_release.ps1` 会通过 Android `aapt` 和 `apksigner` 自动执行以上检查，任一条件不满足都会终止发布。不要直接使用 `flutter build apk --split-per-abi`，以免 Flutter 再次施加 ABI versionCode 偏移。

## 首次配置

1. 将正式签名文件保存在 `example/android/keystore/animemaster-release.jks`。
2. 将签名参数写入 `example/android/key.properties`。
3. 备份这两个文件到安全位置。

## 日常发版

1. 修改 `example/pubspec.yaml` 的 `version`，例如 `2.0.1+2`。
2. 在 `example` 目录执行 `.\tool\build_release.ps1`，一次生成三个 ABI APK和通用 APK，并自动验证版本号、签名与 SHA256。
3. `-SplitPerAbi` 仅为兼容旧命令保留，脚本不会再把它传给 Flutter。
4. 如果需要同时生成应用市场包，追加 `-BuildAppBundle`。

## 输出路径

- 通用 APK: `example/build/app/outputs/flutter-apk/app-release.apk`
- 分 ABI APK: `example/build/app/outputs/flutter-apk/`
- AAB: `example/build/app/outputs/bundle/release/app-release.aab`

## 已安装用户更新流程

AnimeMaster 现在支持"检查更新 + 跳转下载安装"，但 Android 普通侧载应用不能静默强制升级。实际流程如下：

1. 先构建新的 `app-release.apk`。
2. 把 APK 上传到你自己的静态文件地址、对象存储或 GitHub Releases。
3. 运行下面的脚本生成更新清单 JSON：

```powershell
cd F:\AnimeMaster_Engine\AnimeMaster_Engine\example
.\tool\write_update_manifest.ps1 `
  -ApkUrl "https://your-domain.com/anime/app-release.apk" `
  -Notes "修复磁力解析超时","新增播放器选集与倍速"
```

4. 把生成的 `build/app/outputs/flutter-apk/app_update.json` 上传到固定 URL。
5. 在应用设置页把"更新清单地址"填写为这个 JSON 的公开地址。
6. 用户之后可以：
   - 在"关于 AnimeMaster"页手动点"检查更新"。
   - 或者开启"启动时检查更新"，应用启动后自动发现新版本并跳转下载。

## 更新清单格式

```json
{
  "version": "2.0.1",
  "build": 2,
  "apkUrl": "https://your-domain.com/anime/app-release.apk",
  "notes": [
    "修复磁力解析超时",
    "新增播放器选集与倍速"
  ],
  "publishedAt": "2026-04-15T22:00:00+08:00",
  "forceUpdate": false
}
```

# AnimeMaster Android Release

## 固定约束

- 不要修改 `applicationId`，否则旧版本无法覆盖安装。
- 不要更换 release keystore，否则旧版本无法继续升级安装。
- 每次发版前只递增 `example/pubspec.yaml` 里的 `version`。

## 首次配置

1. 将正式签名文件保存在 `example/android/keystore/animemaster-release.jks`。
2. 将签名参数写入 `example/android/key.properties`。
3. 备份这两个文件到安全位置。

## 日常发版

1. 修改 `example/pubspec.yaml` 的 `version`，例如 `2.0.1+2`。
2. 在 `example` 目录执行 `.\tool\build_release.ps1`。
3. 如果需要分 ABI 小包，执行 `.\tool\build_release.ps1 -SplitPerAbi`。
4. 如果需要同时生成应用市场包，执行 `.\tool\build_release.ps1 -BuildAppBundle`。

## 输出路径

- 通用 APK: `example/build/app/outputs/flutter-apk/app-release.apk`
- 分 ABI APK: `example/build/app/outputs/flutter-apk/`
- AAB: `example/build/app/outputs/bundle/release/app-release.aab`

## 已安装用户更新流程

AnimeMaster 现在支持“检查更新 + 跳转下载安装”，但 Android 普通侧载应用不能静默强制升级。实际流程如下：

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
5. 在应用设置页把“更新清单地址”填写为这个 JSON 的公开地址。
6. 用户之后可以：
   - 在“关于 AnimeMaster”页手动点“检查更新”。
   - 或者开启“启动时检查更新”，应用启动后自动发现新版本并跳转下载。

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

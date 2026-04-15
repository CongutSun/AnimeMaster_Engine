# AnimeMaster Android Release

## 固定约束

- 不要修改 `applicationId`，否则旧版本无法覆盖安装。
- 不要更换 release keystore，否则旧版本无法继续更新安装。
- 每次发版前只递增 `example/pubspec.yaml` 中的 `version`。

## 首次配置

1. 将正式签名文件保存在 `example/android/keystore/animemaster-release.jks`。
2. 将签名参数写入 `example/android/key.properties`。
3. 备份这两个文件到安全位置。

## 日常发版

1. 修改 `example/pubspec.yaml` 的 `version`，例如 `1.0.1+2`。
2. 在 `example` 目录执行 `.\tool\build_release.ps1`。
3. 如需减小安装包体积，执行 `.\tool\build_release.ps1 -SplitPerAbi`。
4. 如需同时生成应用市场包，执行 `.\tool\build_release.ps1 -BuildAppBundle`。

## 输出路径

- 通用 APK: `example/build/app/outputs/flutter-apk/app-release.apk`
- 分 ABI APK: `example/build/app/outputs/flutter-apk/`
- AAB: `example/build/app/outputs/bundle/release/app-release.aab`

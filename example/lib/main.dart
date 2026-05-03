import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:animemaster/animemaster.dart'; 

/// 应用程序主入口
///
/// 负责全局初始化并启动引擎提供的业务容器。
void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit 引擎
  MediaKit.ensureInitialized();

  // 初始化 DI 容器
  setupServiceLocator();

  // 恢复持久化的下载任务列表
  await locator<DownloadManager>().initPersistedTasks();

  // 启动来自引擎的完整业务 App
  runApp(const AnimeMasterApp());
}
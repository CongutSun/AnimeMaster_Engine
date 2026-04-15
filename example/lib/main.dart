import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:animemaster/animemaster.dart'; 

/// 应用程序主入口
///
/// 负责全局初始化并启动引擎提供的业务容器。
void main() async {
  // 确保 Flutter 绑定初始化，这是执行异步操作或调用原生通道前必须的步骤
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit 引擎，必须在 UI 渲染前调用以避免红屏异常
  MediaKit.ensureInitialized();
  
  // 恢复持久化的下载任务列表，确保杀后台重启后任务不丢失
  // 这里加上 await，确保数据加载完再挂载 UI
  await DownloadManager().initPersistedTasks();

  // 启动来自引擎的完整业务 App
  runApp(const AnimeMasterApp());
}
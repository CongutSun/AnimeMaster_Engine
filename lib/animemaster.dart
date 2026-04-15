// 移除了不必要的 'library animemaster;' 声明

// ---------------------------------------------------------------------------
// AnimeMaster Engine - Public API Surface
// 
// 本文件是引擎对外的统一接口。只有在此处 export 的类和方法，
// 才能被 example 或其他引入此引擎的 App 使用。
// ---------------------------------------------------------------------------

// 1. 导出底层的 FFI 原生绑定
export 'animemaster_bindings_generated.dart';

// 2. 导出开箱即用的 UI 核心应用组件
export 'src/animemaster_app.dart';

// 3. 导出核心数据与业务模块 (Export Core Business Modules)
export 'src/models/playable_media.dart';
export 'src/models/download_task_info.dart';
export 'src/managers/download_manager.dart';
export 'src/utils/torrent_stream_server.dart';
export 'src/resolvers/torrent_resolver.dart';

// 4. 导出 UI 页面 (Export UI Screens)
export 'src/screens/video_player_page.dart';
export 'src/screens/download_center_page.dart';
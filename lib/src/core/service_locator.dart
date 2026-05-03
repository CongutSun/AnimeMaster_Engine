import '../api/dio_client.dart';
import '../coordinator/episode_coordinator.dart';
import '../managers/download_manager.dart';
import '../services/app_update_service.dart';
import '../services/online_episode_source_service.dart';

/// Lightweight service locator — zero external dependency.
///
/// Register singletons in [setupServiceLocator] at app startup,
/// then access them via typed getters throughout the app.
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator _instance = ServiceLocator._();

  /// Initializes all service singletons. Call once in [main] before [runApp].
  static void setup() {
    _instance
      .._dioClient = DioClient()
      .._downloadManager = DownloadManager()
      .._episodeCoordinator = EpisodeCoordinator()
      .._appUpdateService = const AppUpdateService()
      .._onlineEpisodeSourceService = OnlineEpisodeSourceService();
  }

  static DioClient get dioClient => _instance._dioClient!;
  static DownloadManager get downloadManager => _instance._downloadManager!;
  static EpisodeCoordinator get episodeCoordinator => _instance._episodeCoordinator!;
  static AppUpdateService get appUpdateService => _instance._appUpdateService!;
  static OnlineEpisodeSourceService get onlineEpisodeSourceService =>
      _instance._onlineEpisodeSourceService!;

  DioClient? _dioClient;
  DownloadManager? _downloadManager;
  EpisodeCoordinator? _episodeCoordinator;
  AppUpdateService? _appUpdateService;
  OnlineEpisodeSourceService? _onlineEpisodeSourceService;
}

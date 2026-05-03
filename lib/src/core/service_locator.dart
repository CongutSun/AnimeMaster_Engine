import 'package:get_it/get_it.dart';

import '../api/dio_client.dart';
import '../coordinator/episode_coordinator.dart';
import '../managers/download_manager.dart';
import '../services/app_update_service.dart';
import '../services/online_episode_source_service.dart';

final GetIt locator = GetIt.instance;

void setupServiceLocator() {
  // ── Core infrastructure ──
  locator.registerLazySingleton<DioClient>(() => DioClient());

  // ── State / coordination singletons ──
  locator.registerLazySingleton<DownloadManager>(() => DownloadManager());
  locator.registerLazySingleton<EpisodeCoordinator>(() => EpisodeCoordinator());

  // ── Stateless services ──
  locator.registerLazySingleton<AppUpdateService>(() => const AppUpdateService());
  locator.registerLazySingleton<OnlineEpisodeSourceService>(
    () => OnlineEpisodeSourceService(),
  );
}

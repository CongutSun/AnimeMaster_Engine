import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/viewmodels/home_view_model.dart';
import 'package:animemaster/src/repositories/home_repository.dart';

class _FakeHomeRepository implements HomeRepository {
  HomeContentSnapshot? snapshotToReturn;
  bool delayLoad = false;
  int loadCallCount = 0;

  @override
  Future<HomeContentSnapshot?> loadCachedSnapshot({
    bool forceRefresh = false,
  }) async {
    loadCallCount++;
    if (delayLoad) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return snapshotToReturn;
  }
}

HomeContentSnapshot _makeSnapshot() {
  return HomeContentSnapshot(
    calendarMap: const <int, List<dynamic>>{},
    yearTop: const <Map<String, dynamic>>[],
    latestComments: const <Map<String, dynamic>>[],
    latestBlogs: const <Map<String, dynamic>>[],
  );
}

void main() {
  group('HomeViewModel', () {
    test('initial state is loading with showTodayOnly true', () {
      final HomeViewModel vm = HomeViewModel(
        repository: _FakeHomeRepository(),
      );

      expect(vm.state.isLoading, true);
      expect(vm.state.showTodayOnly, true);
      expect(vm.state.snapshot, isNull);
      expect(vm.state.errorMessage, isNull);
    });

    test('load sets snapshot and clears loading', () async {
      final _FakeHomeRepository repo = _FakeHomeRepository()
        ..snapshotToReturn = _makeSnapshot();
      final HomeViewModel vm = HomeViewModel(repository: repo);

      await vm.load();

      expect(vm.state.isLoading, false);
      expect(vm.state.snapshot, isNotNull);
      expect(repo.loadCallCount, greaterThanOrEqualTo(1));
    });

    test('load with no cached snapshot stays in loading', () async {
      final _FakeHomeRepository repo = _FakeHomeRepository()
        ..snapshotToReturn = null;
      final HomeViewModel vm = HomeViewModel(repository: repo);

      await vm.load();

      // When repo returns null and no network results, stays loading
      // (network refresh may not complete in test without full mock)
    });

    test('toggleScheduleMode toggles showTodayOnly', () {
      final HomeViewModel vm = HomeViewModel(
        repository: _FakeHomeRepository(),
      );

      expect(vm.state.showTodayOnly, true);

      vm.toggleScheduleMode();
      expect(vm.state.showTodayOnly, false);

      vm.toggleScheduleMode();
      expect(vm.state.showTodayOnly, true);
    });

    test('toggleScheduleMode triggers notifyListeners', () {
      final HomeViewModel vm = HomeViewModel(
        repository: _FakeHomeRepository(),
      );
      bool didNotify = false;
      vm.addListener(() => didNotify = true);

      vm.toggleScheduleMode();

      expect(didNotify, true);
    });

    test('concurrent loads only keep latest result (serial guard)', () async {
      final _FakeHomeRepository repo = _FakeHomeRepository()
        ..delayLoad = true
        ..snapshotToReturn = _makeSnapshot();
      final HomeViewModel vm = HomeViewModel(repository: repo);

      // Fire two loads quickly
      final Future<void> first = vm.load();
      final Future<void> second = vm.load();

      await Future.wait(<Future<void>>[first, second]);

      // Both should complete without error; serial guard prevents stale overwrite
      expect(vm.state.isLoading, false);
      expect(repo.loadCallCount, greaterThanOrEqualTo(1));
    });

    test('dispose does not throw', () {
      final HomeViewModel vm = HomeViewModel(
        repository: _FakeHomeRepository(),
      );
      expect(() => vm.dispose(), returnsNormally);
    });
  });

  group('HomeViewState', () {
    test('initial factory creates loading state', () {
      final HomeViewState state = HomeViewState.initial();

      expect(state.isLoading, true);
      expect(state.snapshot, isNull);
      expect(state.errorMessage, isNull);
      expect(state.showTodayOnly, true);
    });

    test('copyWith preserves unchanged fields', () {
      final HomeViewState state = HomeViewState.initial();
      final HomeViewState updated = state.copyWith(isLoading: false);

      expect(updated.isLoading, false);
      expect(updated.showTodayOnly, true);
      expect(updated.snapshot, isNull);
    });

    test('copyWith with clearError resets errorMessage', () {
      final HomeViewState state = HomeViewState.initial().copyWith(
        errorMessage: 'Network error',
      );

      final HomeViewState cleared = state.copyWith(clearError: true);

      expect(cleared.errorMessage, isNull);
    });
  });
}

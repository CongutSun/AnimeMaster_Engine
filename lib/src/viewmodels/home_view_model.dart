import 'package:flutter/foundation.dart';

import '../repositories/home_repository.dart';

class HomeViewState {
  final HomeContentSnapshot? snapshot;
  final bool isLoading;
  final String? errorMessage;
  final bool showTodayOnly;

  const HomeViewState({
    required this.snapshot,
    required this.isLoading,
    required this.errorMessage,
    required this.showTodayOnly,
  });

  factory HomeViewState.initial() {
    return const HomeViewState(
      snapshot: null,
      isLoading: true,
      errorMessage: null,
      showTodayOnly: true,
    );
  }

  HomeViewState copyWith({
    HomeContentSnapshot? snapshot,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? showTodayOnly,
  }) {
    return HomeViewState(
      snapshot: snapshot ?? this.snapshot,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      showTodayOnly: showTodayOnly ?? this.showTodayOnly,
    );
  }
}

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({HomeRepository? repository})
    : _repository = repository ?? HomeRepository();

  final HomeRepository _repository;
  HomeViewState _state = HomeViewState.initial();
  int _loadSerial = 0;

  HomeViewState get state => _state;

  Future<void> load({bool forceRefresh = false}) async {
    final int serial = ++_loadSerial;
    final HomeContentSnapshot? cachedSnapshot = await _repository
        .loadCachedSnapshot(forceRefresh: forceRefresh);
    if (serial != _loadSerial) {
      return;
    }

    if (cachedSnapshot != null) {
      _state = _state.copyWith(
        snapshot: cachedSnapshot,
        isLoading: false,
        clearError: true,
      );
      notifyListeners();
      _refreshFromNetwork(serial: serial, silent: true);
      return;
    }

    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    await _refreshFromNetwork(serial: serial, silent: false);
  }

  void toggleScheduleMode() {
    _state = _state.copyWith(showTodayOnly: !_state.showTodayOnly);
    notifyListeners();
  }

  Future<void> _refreshFromNetwork({
    required int serial,
    required bool silent,
  }) async {
    try {
      final HomeContentSnapshot snapshot = await _repository
          .fetchNetworkSnapshot();
      if (serial != _loadSerial) {
        return;
      }
      _state = _state.copyWith(
        snapshot: snapshot,
        isLoading: false,
        clearError: true,
      );
      notifyListeners();
    } catch (error) {
      debugPrint('[HomeViewModel] Network refresh failed: $error');
      if (serial != _loadSerial || silent) {
        return;
      }
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '数据加载失败，请下拉重试或检查网络状态',
      );
      notifyListeners();
    }
  }
}

import 'package:flutter/foundation.dart';

import '../models/anime.dart';
import '../repositories/search_repository.dart';

class SearchViewState {
  final List<Anime> results;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
  final int currentStart;
  final int currentSubjectType;

  const SearchViewState({
    required this.results,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.errorMessage,
    required this.currentStart,
    required this.currentSubjectType,
  });

  factory SearchViewState.initial() {
    return const SearchViewState(
      results: <Anime>[],
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      errorMessage: null,
      currentStart: 0,
      currentSubjectType: 2,
    );
  }

  SearchViewState copyWith({
    List<Anime>? results,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
    int? currentStart,
    int? currentSubjectType,
  }) {
    return SearchViewState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      currentStart: currentStart ?? this.currentStart,
      currentSubjectType: currentSubjectType ?? this.currentSubjectType,
    );
  }

  static const int maxResults = 25;
}

class SearchViewModel extends ChangeNotifier {
  SearchViewModel({SearchRepository? repository})
    : _repository = repository ?? SearchRepository();

  final SearchRepository _repository;
  SearchViewState _state = SearchViewState.initial();
  int _loadSerial = 0;

  SearchViewState get state => _state;

  Future<void> search(String keyword) async {
    final int serial = ++_loadSerial;
    _state = SearchViewState.initial().copyWith(
      currentSubjectType: _state.currentSubjectType,
    );
    notifyListeners();

    try {
      final List<Anime> results = await _repository.search(
        keyword: keyword,
        type: _state.currentSubjectType,
        start: 0,
        maxResults: SearchViewState.maxResults,
      );
      if (serial != _loadSerial) return;

      _state = _state.copyWith(
        results: results,
        isLoading: false,
        clearError: true,
        hasMore: results.length >= SearchViewState.maxResults,
        currentStart: 0,
      );
      notifyListeners();
    } catch (error) {
      if (serial != _loadSerial) return;
      _state = _state.copyWith(isLoading: false, errorMessage: '搜索失败，请检查网络后重试');
      notifyListeners();
    }
  }

  void setSubjectType(int type) {
    _state = _state.copyWith(currentSubjectType: type);
    notifyListeners();
  }

  Future<void> loadMore(String keyword) async {
    if (_state.isLoading || _state.isLoadingMore || !_state.hasMore) return;

    final int serial = ++_loadSerial;
    _state = _state.copyWith(isLoadingMore: true);
    notifyListeners();

    final int nextStart = _state.currentStart + SearchViewState.maxResults;
    try {
      final List<Anime> results = await _repository.search(
        keyword: keyword,
        type: _state.currentSubjectType,
        start: nextStart,
        maxResults: SearchViewState.maxResults,
      );
      if (serial != _loadSerial) return;

      final List<Anime> merged = <Anime>[..._state.results, ...results];
      _state = _state.copyWith(
        results: merged,
        isLoadingMore: false,
        hasMore: results.length >= SearchViewState.maxResults,
        currentStart: nextStart,
      );
      notifyListeners();
    } catch (_) {
      if (serial != _loadSerial) return;
      _state = _state.copyWith(isLoadingMore: false);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _loadSerial++;
    super.dispose();
  }
}

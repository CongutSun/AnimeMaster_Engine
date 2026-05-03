import 'package:flutter_test/flutter_test.dart';
import 'package:animemaster/src/viewmodels/search_view_model.dart';

void main() {
  group('SearchViewState', () {
    test('initial state has correct defaults', () {
      final SearchViewState state = SearchViewState.initial();

      expect(state.results, isEmpty);
      expect(state.isLoading, true);
      expect(state.isLoadingMore, false);
      expect(state.hasMore, true);
      expect(state.errorMessage, isNull);
      expect(state.currentStart, 0);
      expect(state.currentSubjectType, 2);
    });

    test('copyWith updates only specified fields', () {
      final SearchViewState state = SearchViewState.initial();
      final SearchViewState updated = state.copyWith(
        isLoading: false,
        errorMessage: 'Error',
      );

      expect(updated.isLoading, false);
      expect(updated.errorMessage, 'Error');
      expect(updated.results, isEmpty);
      expect(updated.currentSubjectType, 2);
    });

    test('copyWith clearError resets error message', () {
      final SearchViewState state = SearchViewState.initial().copyWith(
        errorMessage: 'Search failed',
      );

      final SearchViewState cleared = state.copyWith(clearError: true);

      expect(cleared.errorMessage, isNull);
    });

    test('copyWith preserves hasMore when not specified', () {
      final SearchViewState state = SearchViewState.initial();
      final SearchViewState updated = state.copyWith(results: <dynamic>[]);

      expect(updated.hasMore, true);
    });
  });

  group('SearchViewModel', () {
    test('initial state is loading', () {
      final SearchViewModel vm = SearchViewModel();

      expect(vm.state.isLoading, true);
      expect(vm.state.results, isEmpty);
    });

    test('setKeyword updates keyword', () {
      final SearchViewModel vm = SearchViewModel();

      vm.setKeyword('Attack on Titan');

      expect(vm.keyword, 'Attack on Titan');
    });

    test('dispose does not throw', () {
      final SearchViewModel vm = SearchViewModel();
      expect(() => vm.dispose(), returnsNormally);
    });
  });
}

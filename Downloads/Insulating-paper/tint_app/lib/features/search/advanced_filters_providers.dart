// 高級篩選功能的 Riverpod providers

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 高級篩選狀態
class FilterState {
  final Set<String> selectedBrands;
  final String? minVisibleLight;
  final String? maxVisibleLight;
  final String? minHeatRejection;
  final String? maxHeatRejection;

  const FilterState({
    this.selectedBrands = const {},
    this.minVisibleLight,
    this.maxVisibleLight,
    this.minHeatRejection,
    this.maxHeatRejection,
  });

  bool get hasActiveFilters =>
      selectedBrands.isNotEmpty ||
      minVisibleLight != null ||
      maxVisibleLight != null ||
      minHeatRejection != null ||
      maxHeatRejection != null;

  FilterState reset() => const FilterState();

  FilterState copyWith({
    Set<String>? selectedBrands,
    String? minVisibleLight,
    String? maxVisibleLight,
    String? minHeatRejection,
    String? maxHeatRejection,
  }) {
    return FilterState(
      selectedBrands: selectedBrands ?? this.selectedBrands,
      minVisibleLight: minVisibleLight ?? this.minVisibleLight,
      maxVisibleLight: maxVisibleLight ?? this.maxVisibleLight,
      minHeatRejection: minHeatRejection ?? this.minHeatRejection,
      maxHeatRejection: maxHeatRejection ?? this.maxHeatRejection,
    );
  }
}

/// 高級篩選 Provider
final advancedFiltersProvider = StateNotifierProvider<AdvancedFiltersNotifier, FilterState>((ref) {
  return AdvancedFiltersNotifier();
});

class AdvancedFiltersNotifier extends StateNotifier<FilterState> {
  AdvancedFiltersNotifier() : super(const FilterState());

  /// 切換品牌選擇
  void toggleBrand(String brand) {
    final updated = {...state.selectedBrands};
    if (updated.contains(brand)) {
      updated.remove(brand);
    } else {
      updated.add(brand);
    }
    state = state.copyWith(selectedBrands: updated);
  }

  /// 設置可見光範圍
  void setVisibleLightRange(String? min, String? max) {
    state = state.copyWith(
      minVisibleLight: min,
      maxVisibleLight: max,
    );
  }

  /// 設置隔熱範圍
  void setHeatRejectionRange(String? min, String? max) {
    state = state.copyWith(
      minHeatRejection: min,
      maxHeatRejection: max,
    );
  }

  /// 重置所有篩選
  void reset() {
    state = const FilterState();
  }
}

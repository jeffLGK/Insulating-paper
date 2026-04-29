// 高級篩選功能的 Riverpod providers

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 可見光穿透率符合的標準
/// VSCC 認證隔熱紙僅分兩級：符合 40%（未達70%）／符合 70%（70%以上）
enum VisibleLightStandard {
  pct40, // 符合 40%（未達70%）
  pct70, // 符合 70%（70%以上）
}

/// 高級篩選狀態
class FilterState {
  final Set<String> selectedBrands;
  final Set<VisibleLightStandard> visibleLightStandards;

  const FilterState({
    this.selectedBrands = const {},
    this.visibleLightStandards = const {},
  });

  bool get hasActiveFilters =>
      selectedBrands.isNotEmpty || visibleLightStandards.isNotEmpty;

  FilterState reset() => const FilterState();

  FilterState copyWith({
    Set<String>? selectedBrands,
    Set<VisibleLightStandard>? visibleLightStandards,
  }) {
    return FilterState(
      selectedBrands: selectedBrands ?? this.selectedBrands,
      visibleLightStandards: visibleLightStandards ?? this.visibleLightStandards,
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

  /// 切換可見光標準選擇
  void toggleVisibleLightStandard(VisibleLightStandard std) {
    final updated = {...state.visibleLightStandards};
    if (updated.contains(std)) {
      updated.remove(std);
    } else {
      updated.add(std);
    }
    state = state.copyWith(visibleLightStandards: updated);
  }

  /// 重置所有篩選
  void reset() {
    state = const FilterState();
  }
}

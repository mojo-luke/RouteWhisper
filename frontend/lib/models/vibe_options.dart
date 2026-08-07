import 'package:flutter/material.dart';

/// Shared narration-theme / stop-category metadata for anywhere the
/// user picks the trip's "vibe" — the new-trip wizard and
/// TripDetailScreen both need the same list, so it lives here instead
/// of being duplicated (and drifting) in each screen.

class ThemeMeta {
  final String key;
  final String label;
  const ThemeMeta(this.key, this.label);
}

// Keep in sync with backend NarrationTheme literal in app/database.py.
const List<ThemeMeta> narrationThemeChips = [
  ThemeMeta('history', 'History'),
  ThemeMeta('landscape', 'Landscape & nature'),
  ThemeMeta('food_culture', 'Food culture'),
  ThemeMeta('quirky', 'Quirky / weird'),
];

class StopCategoryMeta {
  final String key;
  final String label;
  final IconData icon;
  const StopCategoryMeta(this.key, this.label, this.icon);
}

// Keep in sync with backend StopCategory literal in app/database.py.
const List<StopCategoryMeta> stopCategoryChoices = [
  StopCategoryMeta('food', 'Food', Icons.restaurant),
  StopCategoryMeta('entertainment', 'Entertainment', Icons.music_note),
  StopCategoryMeta('attractions', 'Attractions / sights', Icons.attractions),
  StopCategoryMeta('shopping', 'Shopping', Icons.shopping_bag),
];

StopCategoryMeta categoryMetaFor(String key) => stopCategoryChoices.firstWhere(
      (c) => c.key == key,
      orElse: () => stopCategoryChoices.first,
    );

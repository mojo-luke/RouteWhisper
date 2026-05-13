import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/navigation_service.dart';
import '../services/user_profile_service.dart';

/// Minimal preferences screen — preferred POI categories, default time
/// budget, and (one) dietary toggle. Persisted via PUT /user/profile.
///
/// Optimistic update: on save we PUT the new value, but rely on the
/// returned canonical profile to settle local state. On error we restore
/// the prior value and show a SnackBar.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

// Mirrors backend POICategory enum. Display order is the order users see.
const _allCategories = <_CategoryOption>[
  _CategoryOption('restaurant', 'Restaurants', '🍽️'),
  _CategoryOption('coffee', 'Coffee', '☕'),
  _CategoryOption('gas_station', 'Gas', '⛽'),
  _CategoryOption('scenic', 'Scenic', '🏞️'),
  _CategoryOption('attraction', 'Attractions', '🎯'),
  _CategoryOption('park', 'Parks', '🌳'),
  _CategoryOption('hotel', 'Hotels', '🏨'),
  _CategoryOption('shopping', 'Shopping', '🛍️'),
  _CategoryOption('museum', 'Museums', '🏛️'),
  _CategoryOption('camping', 'Camping', '🏕️'),
  _CategoryOption('grocery', 'Grocery', '🛒'),
  _CategoryOption('pharmacy', 'Pharmacy', '💊'),
];

const _dietaryOptions = <String>['vegetarian', 'vegan', 'gluten_free', 'halal', 'kosher'];

class _CategoryOption {
  final String key;
  final String label;
  final String emoji;
  const _CategoryOption(this.key, this.label, this.emoji);
}

/// Curated suggestion for the "Specific interests" section. Each entry
/// maps to a label the user sees plus the scorer's matching primitives:
/// Mapbox categories (used for the search fan-out + scorer category-hit
/// check) and keywords (matched against `poi.name` so we catch POIs the
/// category alone doesn't bucket cleanly — e.g. "Sunset Vineyards" under
/// `restaurant`).
///
/// Every `mapboxCategories` entry MUST be a value in the backend's
/// POICategory enum until the engine learns to fan out to richer
/// subcategories. Until then, keywords carry the specificity. See
/// docs/recommendations-brief.md → "Personalization vocabulary".
class _CuratedInterest {
  final String label;
  final String emoji;
  final List<String> mapboxCategories;
  final List<String> keywords;
  const _CuratedInterest(
    this.label,
    this.emoji, {
    required this.mapboxCategories,
    this.keywords = const [],
  });
}

const _curatedInterests = <_CuratedInterest>[
  _CuratedInterest('Local diners', '🍳',
      mapboxCategories: ['restaurant'],
      keywords: ['diner', 'café', 'kitchen']),
  _CuratedInterest('Specialty coffee', '☕',
      mapboxCategories: ['coffee'],
      keywords: ['roaster', 'espresso']),
  _CuratedInterest('Wineries', '🍷',
      mapboxCategories: ['restaurant', 'attraction'],
      keywords: ['winery', 'vineyard', 'estate']),
  _CuratedInterest('Craft breweries', '🍺',
      mapboxCategories: ['restaurant'],
      keywords: ['brewery', 'taproom', 'brewing']),
  _CuratedInterest('Scenic overlooks', '🏞️',
      mapboxCategories: ['scenic'],
      keywords: ['overlook', 'viewpoint', 'vista']),
  _CuratedInterest('State parks', '🌲',
      mapboxCategories: ['park'],
      keywords: ['state park', 'state forest']),
  _CuratedInterest('Hiking trails', '🥾',
      mapboxCategories: ['park', 'scenic'],
      keywords: ['trail', 'trailhead']),
  _CuratedInterest('Beaches', '🏖️',
      mapboxCategories: ['scenic'],
      keywords: ['beach']),
  _CuratedInterest('Antique shops', '🪑',
      mapboxCategories: ['shopping'],
      keywords: ['antique', 'vintage']),
  _CuratedInterest('Bookstores', '📚',
      mapboxCategories: ['shopping'],
      keywords: ['bookstore', 'books']),
  _CuratedInterest('Record stores', '💿',
      mapboxCategories: ['shopping'],
      keywords: ['record', 'vinyl']),
  _CuratedInterest('Farmers markets', '🥕',
      mapboxCategories: ['grocery', 'shopping'],
      keywords: ['farmers market', "farmer's market"]),
  _CuratedInterest('Ice cream', '🍦',
      mapboxCategories: ['restaurant'],
      keywords: ['ice cream', 'creamery', 'gelato']),
  _CuratedInterest('BBQ', '🔥',
      mapboxCategories: ['restaurant'],
      keywords: ['bbq', 'barbecue', 'smokehouse']),
  _CuratedInterest('Boutique hotels', '🛏️',
      mapboxCategories: ['hotel'],
      keywords: ['boutique', 'inn']),
  _CuratedInterest('Campgrounds', '⛺',
      mapboxCategories: ['camping'],
      keywords: []),
  _CuratedInterest('EV charging', '🔌',
      mapboxCategories: ['gas_station'],
      keywords: ['charging', 'supercharger', 'evgo', 'chargepoint']),
];

class _PreferencesScreenState extends State<PreferencesScreen> {
  bool _loading = true;
  bool _saving = false;
  UserProfile _profile = const UserProfile();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fetched = await UserProfileService.fetch();
    if (!mounted) return;
    setState(() {
      _profile = fetched ?? const UserProfile();
      _loading = false;
    });
  }

  Future<void> _save(UserProfile next) async {
    final prev = _profile;
    setState(() {
      _profile = next;
      _saving = true;
    });
    final saved = await UserProfileService.save(next);
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _profile = prev;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save preferences')),
      );
    } else {
      setState(() {
        _profile = saved;
        _saving = false;
      });
      // Push voice preference to native so MapActivity knows to
      // skip turn-by-turn instructions when disabled. Fire-and-forget
      // — a transient failure here just means the device hears the
      // voice until the next push (e.g., next app launch).
      NavigationService.controller.bridge.setTurnByTurnVoiceEnabled(
        enabled: saved.turnByTurnVoiceEnabled,
      );
    }
  }

  void _toggleCategory(String key) {
    final current = List<String>.from(_profile.preferredPoiTypes);
    if (current.contains(key)) {
      current.remove(key);
    } else {
      current.add(key);
    }
    _save(_profile.copyWith(preferredPoiTypes: current));
  }

  void _toggleDietary(String key) {
    final current = List<String>.from(_profile.dietaryRestrictions);
    if (current.contains(key)) {
      current.remove(key);
    } else {
      current.add(key);
    }
    _save(_profile.copyWith(dietaryRestrictions: current));
  }

  void _setBudget(int? minutes) {
    _save(_profile.copyWith(
      defaultTimeBudgetMinutes: minutes,
      clearTimeBudget: minutes == null,
    ));
  }

  bool _hasInterestLabel(String label) =>
      _profile.interests.any((i) => i.label.toLowerCase() == label.toLowerCase());

  void _toggleCuratedInterest(_CuratedInterest curated) {
    final current = List<UserInterest>.from(_profile.interests);
    final existingIndex = current.indexWhere(
      (i) => i.label.toLowerCase() == curated.label.toLowerCase(),
    );
    if (existingIndex >= 0) {
      current.removeAt(existingIndex);
    } else {
      current.add(UserInterest(
        label: curated.label,
        mapboxCategories: curated.mapboxCategories,
        keywords: curated.keywords,
      ));
    }
    _save(_profile.copyWith(interests: current));
  }

  void _addCustomInterest(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    if (_hasInterestLabel(trimmed)) return; // dedupe by label
    final current = List<UserInterest>.from(_profile.interests);
    // Free-text entries start with empty mapboxCategories/keywords. The
    // backend's LLM-normalization step (Task #7) populates them at save
    // time; until that lands, these only contribute weight when their
    // label happens to match a POI name verbatim (unlikely).
    current.add(UserInterest(label: trimmed));
    _save(_profile.copyWith(interests: current));
  }

  void _removeInterest(UserInterest interest) {
    final current = _profile.interests
        .where((i) => i.label != interest.label)
        .toList();
    _save(_profile.copyWith(interests: current));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthService.instance.signOut();
              // AuthGate listens to auth-state changes and routes to sign-in.
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(
                  title: 'Stops you like',
                  subtitle: 'POIs in these categories rank higher on your routes.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allCategories.map((opt) {
                    final selected = _profile.preferredPoiTypes.contains(opt.key);
                    return FilterChip(
                      label: Text('${opt.emoji} ${opt.label}'),
                      selected: selected,
                      onSelected: _saving ? null : (_) => _toggleCategory(opt.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                _SectionHeader(
                  title: 'Specific interests',
                  subtitle:
                      'More specific than categories — these carry the heaviest weight in suggestions.',
                ),
                _InterestsSection(
                  selected: _profile.interests,
                  curated: _curatedInterests,
                  saving: _saving,
                  onToggleCurated: _toggleCuratedInterest,
                  onAddCustom: _addCustomInterest,
                  onRemove: _removeInterest,
                ),
                const SizedBox(height: 32),
                _SectionHeader(
                  title: 'Default time budget',
                  subtitle: 'Used as the suggested trip flexibility on new routes.',
                ),
                _BudgetSlider(
                  minutes: _profile.defaultTimeBudgetMinutes,
                  onChanged: _saving ? null : _setBudget,
                ),
                const SizedBox(height: 32),
                _SectionHeader(
                  title: 'Dietary',
                  subtitle: 'Filters restaurant suggestions.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _dietaryOptions.map((d) {
                    final selected = _profile.dietaryRestrictions.contains(d);
                    return FilterChip(
                      label: Text(d.replaceAll('_', ' ')),
                      selected: selected,
                      onSelected: _saving ? null : (_) => _toggleDietary(d),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                _SectionHeader(
                  title: 'Suggestions',
                  subtitle:
                      'Proactive stop ideas the app surfaces during nav.',
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable suggestions during nav'),
                  value: _profile.recommendationsEnabled,
                  onChanged: _saving
                      ? null
                      : (v) => _save(
                            _profile.copyWith(recommendationsEnabled: v),
                          ),
                ),
                _SliderRow(
                  label: 'Max per trip',
                  value: _profile.recommendationsMaxPerTrip.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  formatLabel: (v) => '${v.round()} per trip',
                  onChanged: _saving || !_profile.recommendationsEnabled
                      ? null
                      : (v) => _save(
                            _profile.copyWith(
                              recommendationsMaxPerTrip: v.round(),
                            ),
                          ),
                ),
                _SliderRow(
                  label: 'Min minutes between',
                  value: _profile.recommendationsMinGapMinutes.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  formatLabel: (v) => '${v.round()} min',
                  onChanged: _saving || !_profile.recommendationsEnabled
                      ? null
                      : (v) => _save(
                            _profile.copyWith(
                              recommendationsMinGapMinutes: v.round(),
                            ),
                          ),
                ),
                const SizedBox(height: 32),
                _SectionHeader(
                  title: 'Voice',
                  subtitle:
                      'Turn the Mapbox turn-by-turn voice off if it\'s grating — '
                      'POI narration is separate and stays on either way.',
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Turn-by-turn voice'),
                  subtitle: const Text(
                    'Mapbox\'s "turn left in 200 feet" announcements.',
                  ),
                  value: _profile.turnByTurnVoiceEnabled,
                  onChanged: _saving
                      ? null
                      : (v) => _save(
                            _profile.copyWith(turnByTurnVoiceEnabled: v),
                          ),
                ),
              ],
            ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatLabel;
  final ValueChanged<double>? onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                formatLabel(value),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: formatLabel(value),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
          ],
        ],
      ),
    );
  }
}

class _BudgetSlider extends StatelessWidget {
  final int? minutes;
  final ValueChanged<int?>? onChanged;
  const _BudgetSlider({required this.minutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final value = (minutes ?? 60).clamp(0, 240).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: 0,
                max: 240,
                divisions: 24,
                label: minutes == null
                    ? 'Not set'
                    : '${minutes!} min slack',
                onChanged: onChanged == null
                    ? null
                    : (v) => onChanged!(v.round()),
              ),
            ),
            TextButton(
              onPressed: onChanged == null ? null : () => onChanged!(null),
              child: const Text('Clear'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            minutes == null ? 'No default' : '${minutes!} min of slack per trip',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Composite widget for the "Specific interests" section. Three rows:
///   1. Currently-selected interests as removable chips (only when non-empty)
///   2. Curated suggestion chips (tap to toggle)
///   3. A text field + "Add" button for custom (free-text) interests
class _InterestsSection extends StatefulWidget {
  final List<UserInterest> selected;
  final List<_CuratedInterest> curated;
  final bool saving;
  final void Function(_CuratedInterest) onToggleCurated;
  final void Function(String) onAddCustom;
  final void Function(UserInterest) onRemove;

  const _InterestsSection({
    required this.selected,
    required this.curated,
    required this.saving,
    required this.onToggleCurated,
    required this.onAddCustom,
    required this.onRemove,
  });

  @override
  State<_InterestsSection> createState() => _InterestsSectionState();
}

class _InterestsSectionState extends State<_InterestsSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitCustom() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onAddCustom(text);
    _controller.clear();
  }

  bool _isCuratedSelected(_CuratedInterest c) =>
      widget.selected.any((i) => i.label.toLowerCase() == c.label.toLowerCase());

  /// Match a selected interest back to its curated definition (if any)
  /// so the "selected" chip can show the same emoji the suggestion did.
  /// Returns null for free-text entries.
  _CuratedInterest? _curatedFor(UserInterest interest) {
    for (final c in widget.curated) {
      if (c.label.toLowerCase() == interest.label.toLowerCase()) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.selected.map((interest) {
              final curated = _curatedFor(interest);
              final emoji = curated?.emoji ?? '✨';
              return InputChip(
                avatar: Text(emoji, style: const TextStyle(fontSize: 14)),
                label: Text(interest.label),
                onDeleted: widget.saving ? null : () => widget.onRemove(interest),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
        ],
        Text(
          'Suggestions',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Colors.white60),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.curated.map((c) {
            final selected = _isCuratedSelected(c);
            return FilterChip(
              label: Text('${c.emoji} ${c.label}'),
              selected: selected,
              onSelected:
                  widget.saving ? null : (_) => widget.onToggleCurated(c),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        Text(
          'Add your own',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Colors.white60),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !widget.saving,
                decoration: const InputDecoration(
                  hintText: 'e.g. small wineries, lakes to fish',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitCustom(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: widget.saving ? null : _submitCustom,
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }
}

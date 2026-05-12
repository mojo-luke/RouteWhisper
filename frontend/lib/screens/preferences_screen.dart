import 'package:flutter/material.dart';
import '../services/auth_service.dart';
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

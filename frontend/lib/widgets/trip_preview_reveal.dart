import 'package:flutter/material.dart';

import '../models/route_preview.dart';

/// The "here's your drive" reveal — the payoff step of the trip-creation
/// wizard. Shows real stats immediately, a staged "building" message
/// while generation is still running, then the rundown + a curated set
/// of hotspot cards once ready.
///
/// Deliberately text + town strip only, no map — a map inside a wizard
/// PageView is the riskiest surface to add for a first version (see
/// CLAUDE.md's caution around native map lifecycle), and the reveal
/// reads fine without one.
class TripPreviewReveal extends StatelessWidget {
  final RoutePreview? preview;
  final List<String> preferredThemes;
  final Set<String> selectedHotspotIds;
  final void Function(PreviewHotspot hotspot) onToggleHotspot;
  final VoidCallback? onRetry;

  /// How many of the authored hotspots to show. Kept tight on purpose —
  /// a hand-picked handful reads better here than a scrollable list.
  static const int _shownCount = 4;

  const TripPreviewReveal({
    super.key,
    required this.preview,
    required this.preferredThemes,
    required this.selectedHotspotIds,
    required this.onToggleHotspot,
    this.onRetry,
  });

  List<PreviewHotspot> _curatedHotspots() {
    final all = preview?.hotspots ?? const <PreviewHotspot>[];
    if (preferredThemes.isEmpty) return all.take(_shownCount).toList();
    final preferred = all.where((h) => preferredThemes.contains(h.theme));
    final rest = all.where((h) => !preferredThemes.contains(h.theme));
    return [...preferred, ...rest].take(_shownCount).toList();
  }

  String _stageMessage(String stage) {
    switch (stage) {
      case 'towns':
        return 'Tracing the route…';
      case 'authoring':
        return 'Writing up what\'s out there…';
      case 'done':
        return 'Ready.';
      default:
        return 'Tracing the route…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    if (p == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatsHeader(preview: p),
        const SizedBox(height: 20),
        if (p.isFailed)
          _FailureState(error: p.error, onRetry: onRetry)
        else if (!p.isReady)
          _BuildingState(message: _stageMessage(p.stage), towns: p.towns)
        else ...[
          if (p.rundown.isNotEmpty) _RundownCard(rundown: p.rundown),
          const SizedBox(height: 20),
          if (_curatedHotspots().isNotEmpty) ...[
            Text(
              'Along the way',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final hotspot in _curatedHotspots())
              _HotspotCard(
                hotspot: hotspot,
                selected: selectedHotspotIds.contains(hotspot.id),
                onToggle: () => _handleToggle(context, hotspot),
              ),
          ],
        ],
      ],
    );
  }

  void _handleToggle(BuildContext context, PreviewHotspot hotspot) {
    final wasSelected = selectedHotspotIds.contains(hotspot.id);
    onToggleHotspot(hotspot);
    if (wasSelected) return;
    // 5-second undo SnackBar on this state-changing action, per
    // CLAUDE.md rule 3.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${hotspot.title}"'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => onToggleHotspot(hotspot),
        ),
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  final RoutePreview preview;
  const _StatsHeader({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(icon: Icons.straighten, label: preview.distanceLabel),
        const SizedBox(width: 8),
        _StatChip(icon: Icons.schedule, label: preview.durationLabel),
        if (preview.towns.isNotEmpty) ...[
          const SizedBox(width: 8),
          _StatChip(
            icon: Icons.location_city,
            label: '${preview.towns.length} towns',
          ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _BuildingState extends StatelessWidget {
  final String message;
  final List<PreviewTown> towns;
  const _BuildingState({required this.message, required this.towns});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(message, style: const TextStyle(color: Colors.white70)),
          ],
        ),
        if (towns.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: towns
                .map((t) => Chip(
                      label: Text(t.name),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _FailureState extends StatelessWidget {
  final String? error;
  final VoidCallback? onRetry;
  const _FailureState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Couldn't finish writing this up.",
          style: TextStyle(color: Colors.white70),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}

class _RundownCard extends StatelessWidget {
  final String rundown;
  const _RundownCard({required this.rundown});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(rundown, style: const TextStyle(height: 1.4)),
      ),
    );
  }
}

class _HotspotCard extends StatelessWidget {
  final PreviewHotspot hotspot;
  final bool selected;
  final VoidCallback onToggle;

  const _HotspotCard({
    required this.hotspot,
    required this.selected,
    required this.onToggle,
  });

  IconData get _themeIcon {
    switch (hotspot.theme) {
      case 'history':
        return Icons.museum_outlined;
      case 'landscape':
        return Icons.landscape_outlined;
      case 'food_culture':
        return Icons.restaurant_outlined;
      default:
        return Icons.emoji_objects_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_themeIcon, size: 14, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        'NEAR ${hotspot.town.toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hotspot.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(hotspot.blurb, style: const TextStyle(height: 1.3)),
                  if (hotspot.detourHint != null &&
                      hotspot.detourHint!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Chip(
                      label: Text(hotspot.detourHint!),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                selected ? Icons.check_circle : Icons.add_location_alt_outlined,
                color: selected ? Colors.greenAccent : null,
              ),
              tooltip: selected ? 'Remove stop' : 'Add stop',
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/discovery_item.dart';
import '../services/narration_feedback_service.dart';

/// The user's Discoveries timeline — every fact they've saved,
/// visited, or heard, merged by pageid and sorted by most recent
/// activity. The souvenir layer for Phase 2 talkback.
///
/// Each card shows the place's name, a snippet from the friend-voice
/// summary, and status badges (⭐ saved, ✓ visited, 🗣 heard). Tap a
/// card to expand → see the full summary + a "Read on Wikipedia"
/// link. Unsave / Save toggle lives on the expanded view.
///
/// v1 has no filter chips. Add them in a follow-up if the list gets
/// dense enough to need them.
class DiscoveriesScreen extends StatefulWidget {
  const DiscoveriesScreen({super.key});

  @override
  State<DiscoveriesScreen> createState() => _DiscoveriesScreenState();
}

class _DiscoveriesScreenState extends State<DiscoveriesScreen> {
  bool _loading = true;
  List<DiscoveryItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final items = await NarrationFeedbackService.listDiscoveries();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discoveries')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _DiscoveryTile(item: _items[i], onChanged: _refresh),
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_outlined,
              size: 56,
              color: Colors.white.withOpacity(0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'No discoveries yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Drive somewhere interesting and the places you hear about, '
              'save, or visit will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryTile extends StatefulWidget {
  final DiscoveryItem item;
  final VoidCallback onChanged;
  const _DiscoveryTile({required this.item, required this.onChanged});

  @override
  State<_DiscoveryTile> createState() => _DiscoveryTileState();
}

class _DiscoveryTileState extends State<_DiscoveryTile> {
  bool _expanded = false;
  bool _busy = false;

  Future<void> _toggleSave() async {
    setState(() => _busy = true);
    final pageid = widget.item.wikipediaPageid;
    final wasSaved = widget.item.isSaved;
    final success = wasSaved
        ? await NarrationFeedbackService.unsaveFact(pageid: pageid)
        : await NarrationFeedbackService.saveFact(
            pageid: pageid,
            articleTitle: widget.item.articleTitle,
            articleUrl: widget.item.articleUrl,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (success) {
      // Reload the parent list so timestamps + sort order reflect
      // the toggle.
      widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasSaved
              ? 'Failed to unsave'
              : 'Failed to save — try again later'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final badges = <Widget>[];
    if (item.isSaved) {
      badges.add(const _Badge(icon: Icons.star, label: 'Saved'));
    }
    if (item.isVisited) {
      badges.add(const _Badge(icon: Icons.check_circle, label: 'Visited'));
    }
    if (item.isHeard) {
      badges.add(const _Badge(icon: Icons.record_voice_over, label: 'Heard'));
    }

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.articleTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.white60,
                ),
              ],
            ),
            if (item.primary != null && item.primary!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.primary!,
                maxLines: _expanded ? 999 : 2,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ],
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: badges),
            ],
            if (_expanded) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    icon: Icon(
                      item.isSaved ? Icons.star : Icons.star_border,
                      color: item.isSaved ? Colors.amber : null,
                      size: 18,
                    ),
                    label: Text(item.isSaved ? 'Saved' : 'Save'),
                    onPressed: _busy ? null : _toggleSave,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

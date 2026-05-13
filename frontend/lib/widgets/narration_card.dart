import 'package:flutter/material.dart';

import '../services/narration_service.dart';
import '../services/navigation_service.dart';

/// Visual surface for the active whisper.
///
/// Subscribes to `NavigationService.narration` (a ChangeNotifier) and
/// renders the most recent narration with Replay / Tell me more /
/// Dismiss buttons. When `narration.current` is null, the widget
/// renders nothing — Phase 1 keeps the dashboard quiet when nothing's
/// been whispered yet.
///
/// During active nav the user is in MapActivity (native), so this
/// card is mostly visible pre-nav and on returns to the dashboard.
/// The native banner version comes in a follow-up commit; the audio
/// itself fires either way.
class NarrationCard extends StatefulWidget {
  final NarrationService? service;
  const NarrationCard({super.key, this.service});

  @override
  State<NarrationCard> createState() => _NarrationCardState();
}

class _NarrationCardState extends State<NarrationCard> {
  late final NarrationService _service =
      widget.service ?? NavigationService.narration;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final active = _service.current;
    if (active == null) {
      // No active whisper yet. If we're still loading the trip's
      // facts (first cache fill can take 20-60s on a cold backend),
      // show a quiet placeholder so the user knows the system is
      // working rather than wondering why it's silent.
      if (_service.isLoading) {
        return const Card(
          margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Loading whispers for this route…',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.record_voice_over, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.fact.articleTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Dismiss',
                  onPressed: _service.dismissActive,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _currentText(active),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Replay'),
                  onPressed: _service.replay,
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.expand_more, size: 18),
                  label: Text(_tellMeMoreLabel(active)),
                  onPressed: _service.canTellMore ? _service.tellMeMore : null,
                ),
                const Spacer(),
                // Star toggle: explicit "remember this for later"
                // signal. State is hydrated from the backend at trip
                // start so previously-saved facts already show
                // filled on the first whisper.
                IconButton(
                  tooltip: _service.isSaved(active.fact.wikipediaPageid)
                      ? 'Saved'
                      : 'Save for later',
                  icon: Icon(
                    _service.isSaved(active.fact.wikipediaPageid)
                        ? Icons.star
                        : Icons.star_border,
                    color: _service.isSaved(active.fact.wikipediaPageid)
                        ? Colors.amber
                        : null,
                  ),
                  onPressed: _service.toggleSaveActive,
                ),
              ],
            ),
            if (!_service.canTellMore && (active.fact.isThin || _outOfFollowUps(active)))
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  "That's all I've got on this one.",
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What's currently being shown. After "Tell me more" advances, we
  /// surface the follow-up that was just spoken (the index already
  /// advanced, so look at index - 1).
  String _currentText(active) {
    final i = _service.followUpIndex;
    if (i == 0) return active.fact.primary;
    return active.fact.followUps[i - 1];
  }

  String _tellMeMoreLabel(active) {
    if (active.fact.isThin) return 'No more';
    final remaining = active.fact.followUps.length - _service.followUpIndex;
    if (remaining <= 0) return 'No more';
    return 'Tell me more ($remaining)';
  }

  bool _outOfFollowUps(active) =>
      _service.followUpIndex >= active.fact.followUps.length;
}

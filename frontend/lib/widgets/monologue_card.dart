import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/narration_service.dart';

/// Lightweight visible surface for the drive-monologue track.
///
/// Shows the most-recently-fired monologue utterance with its anchor
/// town and the text we just spoke. Auto-dismisses after
/// [NarrationService.monologueCardDuration] (~20s) so it doesn't
/// linger forever; a manual close (×) is also available.
///
/// Distinct from [NarrationCard] in three ways:
///   - No save / take-me-there / tell-me-more affordances. A
///     monologue utterance isn't a pageid-backed fact; it's
///     authored prose tied to a town.
///   - No replay. The audio handoff to the native MediaPlayer is
///     one-shot; we don't keep the bytes around to re-trigger.
///   - Smaller, leans on tonal/secondary colors so it doesn't
///     compete with the per-POI card when both are on screen.
///
/// Renders [SizedBox.shrink] when no monologue is active so the
/// surrounding layout doesn't shift when one arrives.
class MonologueCard extends StatelessWidget {
  /// Optional injection seam for tests. Production reads from the
  /// Provider tree.
  final NarrationService? service;
  const MonologueCard({super.key, this.service});

  @override
  Widget build(BuildContext context) {
    final svc = service ?? context.watch<NarrationService>();
    final utt = svc.currentMonologueUtterance;
    if (utt == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Material(
        elevation: 0,
        color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.record_voice_over,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer.withOpacity(0.8),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      utt.anchor.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: theme.colorScheme.onSecondaryContainer
                            .withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      utt.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Dismiss',
                onPressed: svc.dismissMonologueCard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

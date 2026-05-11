import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/navigation_service.dart';
import '../services/recommendation_service.dart';
import 'recommendation_card.dart';

/// Wraps the whole app so any active route gets a recommendation card
/// floating at the bottom whenever the service has one to surface.
///
/// Why a top-level Stack instead of pushing a Flutter route: during
/// navigation we don't reliably own the foreground (the native
/// MapActivity does). A Stack baked into MaterialApp's `builder` paints
/// over whatever Flutter content is showing without fighting the
/// Navigator. When MapActivity is foreground and the Flutter overlay
/// container isn't visible, native sees the suggestion via the polled
/// event surface (TODO follow-up) — for now the overlay only renders
/// while the Flutter side is on top.
///
/// Also drives the service lifecycle: starts polling when the nav
/// controller enters `navigating`, stops + resets on exit.
class RecommendationOverlay extends StatefulWidget {
  final Widget? child;
  const RecommendationOverlay({super.key, required this.child});

  @override
  State<RecommendationOverlay> createState() => _RecommendationOverlayState();
}

class _RecommendationOverlayState extends State<RecommendationOverlay> {
  NavigationState? _lastSeenState;

  @override
  Widget build(BuildContext context) {
    final navState = context.watch<NavigationController>().currentState;
    final service = context.read<RecommendationService>();

    // Drive the polling lifecycle off nav-state edges. Schedule the call
    // after this frame so we never mutate provider state during build.
    if (_lastSeenState != navState) {
      final prev = _lastSeenState;
      _lastSeenState = navState;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navState == NavigationState.navigating &&
            prev != NavigationState.navigating) {
          service.resetForNewTrip();
          service.start();
        } else if (navState != NavigationState.navigating) {
          service.stop();
        }
      });
    }

    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: RecommendationCard(),
        ),
      ],
    );
  }
}

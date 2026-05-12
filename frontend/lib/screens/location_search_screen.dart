import 'dart:async';

import 'package:flutter/material.dart';

import '../services/geocoding_service.dart';

/// Modal search screen used by the new-trip wizard to pick an origin or
/// destination. Returns the chosen [GeocodeCandidate] via Navigator.pop,
/// or null if the user backs out. Debounces input by 350 ms so we don't
/// fire a geocode request on every keystroke.
class LocationSearchScreen extends StatefulWidget {
  final String title;
  final String hint;

  const LocationSearchScreen({
    super.key,
    required this.title,
    this.hint = 'Search city, address, or landmark',
  });

  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<GeocodeCandidate> _results = const [];
  String _activeQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(trimmed);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _activeQuery = query;
    });
    final results = await GeocodingService.search(query);
    if (!mounted || _activeQuery != query) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
              onChanged: (v) {
                setState(() {}); // toggle clear button
                _onChanged(v);
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.text.trim().isEmpty) {
      return const _Hint(
        icon: Icons.travel_explore,
        text: 'Type a place name to search.',
      );
    }
    if (!_loading && _results.isEmpty) {
      return const _Hint(
        icon: Icons.search_off,
        text: 'No matches. Try a different query.',
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final candidate = _results[i];
        return ListTile(
          leading: const Icon(Icons.place_outlined),
          title: Text(
            candidate.name.isEmpty ? candidate.displayLine : candidate.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: candidate.fullAddress != null && candidate.fullAddress!.isNotEmpty
              ? Text(
                  candidate.fullAddress!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onTap: () => Navigator.of(context).pop(candidate),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

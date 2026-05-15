/// Dart port of Google's polyline encoding algorithm at precision 6.
///
/// Mapbox Navigation SDK + Directions API emit polylines at precision
/// 6 (not the more common precision 5 from Google Maps), and we
/// persist them server-side in `Trip.polyline`. This decoder turns
/// that string back into `[lat, lng]` pairs the canvas can render.
///
/// Mirrors `backend/app/utils/polyline.py::decode_polyline` so a
/// round-trip through either side gives the same coordinates.
List<List<double>> decodePolyline(String polyline, {int precision = 6}) {
  if (polyline.isEmpty) return const [];
  final factor = 1 << (precision == 5 ? 0 : 0);  // unused; kept readable
  final divisor = 1 / _pow10(precision).toDouble();

  final coordinates = <List<double>>[];
  int index = 0;
  int lat = 0;
  int lng = 0;
  final length = polyline.length;

  while (index < length) {
    // Decode latitude delta
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= length) return coordinates;
      byte = polyline.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dLat;

    // Decode longitude delta
    result = 0;
    shift = 0;
    do {
      if (index >= length) return coordinates;
      byte = polyline.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dLng;

    coordinates.add([lat * divisor, lng * divisor]);
  }
  // Silence unused warning if any tooling complains.
  // ignore: unused_local_variable
  final _ = factor;
  return coordinates;
}

int _pow10(int n) {
  var x = 1;
  for (var i = 0; i < n; i++) {
    x *= 10;
  }
  return x;
}

/// Round-tripping other people's files.
///
/// A chart on someone's phone may have been written by a newer game build, or
/// by a tool that keeps its own bookkeeping in the file. If this app parsed
/// only the fields it knows and wrote back only those, saving would quietly
/// delete the rest. So every model keeps the keys it did not claim and folds
/// them back in on write.
mixin JsonExtras {
  /// Keys from the source object that no field of this model claimed.
  final Map<String, dynamic> extras = <String, dynamic>{};

  /// Remember everything in [source] except [claimed].
  void keepExtras(Map<String, dynamic> source, Set<String> claimed) {
    extras.clear();
    for (final entry in source.entries) {
      if (!claimed.contains(entry.key)) extras[entry.key] = entry.value;
    }
  }

  /// [written] plus the unclaimed keys. Fields this app knows win, so an edit
  /// is never overruled by the stale copy of the same key.
  Map<String, dynamic> withExtras(Map<String, dynamic> written) {
    if (extras.isEmpty) return written;
    return <String, dynamic>{...extras, ...written};
  }
}

/// Drop keys whose value is null, the way the game's writer does. Optional
/// fields it never set are absent from the file rather than present as null.
Map<String, dynamic> pruneNulls(Map<String, dynamic> map) {
  map.removeWhere((_, value) => value == null);
  return map;
}

double asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// A number that came out of JSON as a whole value should go back as one.
/// Writing `600.0` where the file said `600` makes a diff out of nothing.
num compactNumber(double value) {
  if (value.isFinite && value == value.roundToDouble()) return value.toInt();
  return value;
}

List<String> asStringList(dynamic value) {
  if (value is List) return value.map((item) => '$item').toList();
  return <String>[];
}

Map<String, double> asDoubleMap(dynamic value) {
  final result = <String, double>{};
  if (value is Map) {
    value.forEach((key, item) => result['$key'] = asDouble(item));
  }
  return result;
}

Map<String, int> asIntMap(dynamic value) {
  final result = <String, int>{};
  if (value is Map) {
    value.forEach((key, item) => result['$key'] = asInt(item));
  }
  return result;
}

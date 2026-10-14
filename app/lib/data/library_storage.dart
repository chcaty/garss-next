import 'package:shared_preferences/shared_preferences.dart';

/// Small storage boundary so rejected writes and interrupted upgrades are testable.
abstract interface class LibraryStorage {
  Object? read(String key);
  Future<bool> write(String key, Object value);
}

class PreferencesLibraryStorage implements LibraryStorage {
  PreferencesLibraryStorage(this.preferences);
  final SharedPreferences preferences;

  @override
  Object? read(String key) => preferences.get(key);

  @override
  Future<bool> write(String key, Object value) => switch (value) {
    String value => preferences.setString(key, value),
    List<String> value => preferences.setStringList(key, value),
    double value => preferences.setDouble(key, value),
    bool value => preferences.setBool(key, value),
    _ => throw ArgumentError.value(value, key, 'Unsupported preference type'),
  };
}

class LibraryStorageException implements Exception {
  const LibraryStorageException(this.key);
  final String key;
}

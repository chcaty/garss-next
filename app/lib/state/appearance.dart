import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appearanceProvider =
    AsyncNotifierProvider<AppearanceController, ThemeMode>(
      AppearanceController.new,
    );

class AppearanceController extends AsyncNotifier<ThemeMode> {
  Future<void> _writes = Future.value();
  @override
  Future<ThemeMode> build() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getInt('appearance') ?? 0;
    return value >= 0 && value < ThemeMode.values.length
        ? ThemeMode.values[value]
        : ThemeMode.system;
  }

  Future<bool> change(ThemeMode mode) async {
    state = AsyncData(mode);
    bool saved = true;
    _writes = _writes.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        saved = await preferences.setInt('appearance', mode.index);
      } catch (_) {
        saved = false;
      }
    });
    await _writes;
    return saved;
  }
}

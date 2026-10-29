import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  bool _loaded = false;

  ThemeMode get mode => _mode;

  ThemeService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('theme_mode') ?? 'dark';
    if (_loaded) return;
    _mode = v == 'light' ? ThemeMode.light : ThemeMode.dark;
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggle() async {
    _loaded = true;
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'theme_mode', _mode == ThemeMode.light ? 'light' : 'dark');
  }
}

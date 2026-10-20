import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Dark tokens ───────────────────────────────────────────────────────────────
const kBg            = Color(0xFF0F0F1A);
const kSurface       = Color(0xFF1A1A2E);
const kBorder        = Color(0xFF2A2A4A);
const kAccent        = Color(0xFF6C63FF);
const kSuccess       = Color(0xFF22C55E);
const kWarning       = Color(0xFFFFBE0B);
const kError         = Color(0xFFFF6B6B);
const kInfo          = Color(0xFF4ECDC4);
const kOrange        = Color(0xFFFF9F43);
const kTextPrimary   = Colors.white;
const kTextSecondary = Color(0xFF9E9EBE);
const kTextMuted     = Color(0xFF6B6B8A);

// ── Light tokens ──────────────────────────────────────────────────────────────
const kBgLight            = Color(0xFFF4F4F8);
const kSurfaceLight       = Color(0xFFFFFFFF);
const kBorderLight        = Color(0xFFE2E2EE);
const kAccentLight        = Color(0xFF6C63FF);
const kSuccessLight       = Color(0xFF16A34A);
const kWarningLight       = Color(0xFFD97706);
const kErrorLight         = Color(0xFFDC2626);
const kInfoLight          = Color(0xFF0D9488);
const kOrangeLight        = Color(0xFFEA6C00);
const kTextPrimaryLight   = Color(0xFF0F0F1A);
const kTextSecondaryLight = Color(0xFF5A5A7A);
const kTextMutedLight     = Color(0xFF9494AA);

// ── Theme mode notifier (persistent) ─────────────────────────────────────────
class ThemeNotifier extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeNotifier() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _mode = switch (saved) {
      'dark'  => ThemeMode.dark,
      'light' => ThemeMode.light,
      _       => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, switch (m) {
      ThemeMode.dark  => 'dark',
      ThemeMode.light => 'light',
      _               => 'system',
    });
  }
}

final themeNotifier = ThemeNotifier();

// ── ThemeData builders ────────────────────────────────────────────────────────
ThemeData buildDarkTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
    surface: kBg,
  ),
  scaffoldBackgroundColor: kBg,
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: kBg,
    foregroundColor: kTextPrimary,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: kTextPrimary,
      fontWeight: FontWeight.w800,
      fontSize: 20,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kAccent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kAccent,
      side: const BorderSide(color: kAccent),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    hintStyle: const TextStyle(color: kTextMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAccent),
    ),
  ),
  cardTheme: CardThemeData(
    color: kSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: kBorder),
    ),
    elevation: 0,
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: kSurface,
    contentTextStyle: TextStyle(color: kTextPrimary),
  ),
);

ThemeData buildLightTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: kAccentLight,
    brightness: Brightness.light,
    surface: kBgLight,
  ),
  scaffoldBackgroundColor: kBgLight,
  useMaterial3: true,
  appBarTheme: const AppBarTheme(
    backgroundColor: kBgLight,
    foregroundColor: kTextPrimaryLight,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: kTextPrimaryLight,
      fontWeight: FontWeight.w800,
      fontSize: 20,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kAccentLight,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kAccentLight,
      side: const BorderSide(color: kAccentLight),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurfaceLight,
    hintStyle: const TextStyle(color: kTextMutedLight),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAccentLight),
    ),
  ),
  cardTheme: CardThemeData(
    color: kSurfaceLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: kBorderLight),
    ),
    elevation: 0,
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: kSurfaceLight,
    contentTextStyle: TextStyle(color: kTextPrimaryLight),
  ),
);
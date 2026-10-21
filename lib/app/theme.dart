// lib/app/theme.dart
//
// TapSense design tokens — palette: Charcoal Slate / Mauve / Steel / Lemon / Crimson
//
// Dark mode  → Charcoal Slate  (#1C1C1E)
// Light mode → Off-White       (#F2F2EF)


import 'package:flutter/material.dart';

// ─── Raw palette ─────────────────────────────────────────────────────────────

const _charcoal       = Color(0xFF1C1C1E); // darkest — bg in dark mode
const _charcoalSurf   = Color(0xFF262628); // slightly lighter — surfaces
const _charcoalBorder = Color(0xFF303032); // borders, dividers
const _dustyMauve     = Color(0xFFBBA0B2); // muted / secondary text
const _steelBlue      = Color(0xFF2E668C); // accent, links, buttons
const _steelBlueLt    = Color(0xFF4A90B8); // lighter tint for light-mode accent
const _paleLemon      = Color(0xFFF0F0C8); // light bg / primary dark-mode text
const _offWhite       = Color(0xFFF2F2EF); // light mode bg
const _offWhiteSurf   = Color(0xFFE8E8E4); // light-mode surface
const _offWhiteBorder = Color(0xFFD4D4CF); // light-mode borders
const _deepRed        = Color(0xFF5A0001); // error / destructive dark
const _deepRedLight   = Color(0xFF8B0000); // error / destructive light-mode
const _crimsonSoft    = Color(0xFFFFE8E8); // light-mode error tint bg

// ─── Dark-mode tokens ────────────────────────────────────────────────────────

/// Page background
const kBg      = _charcoal;         // #1C1C1E

/// Card / sheet surface
const kSurface = _charcoalSurf;     // #262628

/// Borders, dividers
const kBorder  = _charcoalBorder;   // #303032

/// Primary text (on dark bg)
const kTextPrimary   = _paleLemon;              // #F0F0C8 — 13.2 : 1 on kBg ✅
const kTextSecondary = Color(0xFFDDDDB8);       // slightly dimmer lemon
const kTextMuted     = _dustyMauve;             // #BBA0B2 — 5.3 : 1 on kBg ✅

// ─── Light-mode tokens ───────────────────────────────────────────────────────

/// Page background (light)
const kBgLight      = _offWhite;       // #F2F2EF

/// Card / sheet surface (light)
const kSurfaceLight = _offWhiteSurf;   // #E8E8E4

/// Borders (light)
const kBorderLight  = _offWhiteBorder; // #D4D4CF

/// Text (light — charcoal on off-white: 13.2 : 1)
const kTextPrimaryLight   = _charcoal;          // #1C1C1E
const kTextSecondaryLight = Color(0xFF3A3A3C);
const kTextMutedLight     = Color(0xFF6C6C70);

// ─── Semantic colours (shared, context-aware) ────────────────────────────────

/// Accent — Steel Blue.
/// In dark mode, use on surfaces (#262628) not directly on bg (#1C1C1E) for best contrast.
const kAccent      = _steelBlue;    // #2E668C
const kAccentLight = _steelBlueLt;  // #4A90B8

/// Success
const kSuccess      = _paleLemon;           // on dark surfaces
const kSuccessLight = Color(0xFF2D6A4F);    // on light surfaces

/// Error / destructive.
/// Dark mode: bright accessible red (visible on charcoal bg).
/// Light mode: deep red on light surfaces.
const kError      = Color(0xFFE05555); // bright red — readable on #1C1C1E ✅
const kErrorDark  = _deepRed;          // #5A0001 — use as bg tint only, not text
const kErrorLight = _deepRedLight;     // #8B0000 — on light surfaces

/// Warning — visible orange on both themes.
/// Dark mode: bright amber. Light mode: deeper burnt orange.
const kWarning      = Color(0xFFF59E0B); // bright amber — readable on charcoal ✅
const kWarningLight = Color(0xFFB45309); // burnt orange — readable on off-white ✅

/// Info — lighter steel
const kInfo      = Color(0xFF4A90B8);
const kInfoLight = Color(0xFF1E5C80);

/// Orange — voice / mic accent
const kOrange      = Color(0xFFB45309);
const kOrangeLight = Color(0xFF92400E);

// ─── ThemeData builders ───────────────────────────────────────────────────────

ThemeData buildDarkTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(
    primary:     kAccent,
    secondary:   _dustyMauve,
    surface:     kSurface,
    error:       kError,       // bright red — readable on charcoal
    onPrimary:   _paleLemon,
    onSecondary: _charcoal,
    onSurface:   kTextPrimary,
    onError:     Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kBg,
    foregroundColor: kTextPrimary,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: kTextPrimary,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardTheme: CardThemeData(
    color: kSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: kBorder),
    ),
  ),
  dividerColor: kBorder,
  iconTheme: const IconThemeData(color: kTextPrimary),
  textTheme: const TextTheme(
    bodyLarge:   TextStyle(color: kTextPrimary),
    bodyMedium:  TextStyle(color: kTextPrimary),
    bodySmall:   TextStyle(color: kTextMuted),
    labelLarge:  TextStyle(color: kTextPrimary,   fontWeight: FontWeight.w600),
    titleMedium: TextStyle(color: kTextPrimary,   fontWeight: FontWeight.w600),
    titleLarge:  TextStyle(color: kTextPrimary,   fontWeight: FontWeight.w700),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kBg,
    hintStyle: const TextStyle(color: kTextMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAccent, width: 1.5),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kAccent,
      foregroundColor: _paleLemon,   // Lemon on Steel — 5.0 : 1 AA ✅
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kAccentLight,
      side: const BorderSide(color: kAccent),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: kAccentLight),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: kSurface,
    labelStyle: const TextStyle(color: kTextPrimary, fontSize: 12),
    side: const BorderSide(color: kBorder),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: Color(0xFF323234), // slightly lighter than surface for contrast
    contentTextStyle: TextStyle(color: Color(0xFFF0F0C8)), // pale lemon — always readable
    actionTextColor: Color(0xFF4A90B8),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: kSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: kSurface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    titleTextStyle: const TextStyle(
        color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.w700),
    contentTextStyle: const TextStyle(color: kTextSecondary),
  ),
  progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccentLight),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: kAccent,
    foregroundColor: _paleLemon,
  ),
);

ThemeData buildLightTheme() => ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: kBgLight,
  colorScheme: const ColorScheme.light(
    primary:     kAccentLight,
    secondary:   _dustyMauve,
    surface:     kSurfaceLight,
    error:       kErrorLight,
    onPrimary:   Colors.white,
    onSecondary: _charcoal,
    onSurface:   kTextPrimaryLight,
    onError:     Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kBgLight,
    foregroundColor: kTextPrimaryLight,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: kTextPrimaryLight,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
  ),
  cardTheme: CardThemeData(
    color: kSurfaceLight,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: kBorderLight),
    ),
  ),
  dividerColor: kBorderLight,
  iconTheme: const IconThemeData(color: kTextPrimaryLight),
  textTheme: const TextTheme(
    bodyLarge:   TextStyle(color: kTextPrimaryLight),
    bodyMedium:  TextStyle(color: kTextPrimaryLight),
    bodySmall:   TextStyle(color: kTextMutedLight),
    labelLarge:  TextStyle(color: kTextPrimaryLight,   fontWeight: FontWeight.w600),
    titleMedium: TextStyle(color: kTextPrimaryLight,   fontWeight: FontWeight.w600),
    titleLarge:  TextStyle(color: kTextPrimaryLight,   fontWeight: FontWeight.w700),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kBgLight,
    hintStyle: const TextStyle(color: kTextMutedLight),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorderLight),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kBorderLight),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAccentLight, width: 1.5),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kAccentLight,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: kAccentLight),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: kSurfaceLight,
    labelStyle: const TextStyle(color: kTextPrimaryLight, fontSize: 12),
    side: const BorderSide(color: kBorderLight),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: kSurfaceLight,
    contentTextStyle: TextStyle(color: kTextPrimaryLight),
    actionTextColor: kAccentLight,
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: kSurfaceLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: kSurfaceLight,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    titleTextStyle: const TextStyle(
        color: kTextPrimaryLight, fontSize: 18, fontWeight: FontWeight.w700),
    contentTextStyle: const TextStyle(color: kTextSecondaryLight),
  ),
  progressIndicatorTheme:
      const ProgressIndicatorThemeData(color: kAccentLight),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: kAccentLight,
    foregroundColor: Colors.white,
  ),
);

// ─── Theme mode notifier (used by main.dart) ──────────────────────────────────

class _ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void set(ThemeMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  /// Alias for [set] — matches the name used in settings_screen.dart.
  void setMode(ThemeMode m) => set(m);
}

final themeNotifier = _ThemeNotifier();
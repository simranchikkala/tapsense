import 'package:flutter/material.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
const kBg        = Color(0xFF0F0F1A);  // page background
const kSurface   = Color(0xFF1A1A2E);  // cards, inputs
const kBorder    = Color(0xFF2A2A4A);  // subtle borders
const kAccent    = Color(0xFF6C63FF);  // primary purple
const kSuccess   = Color(0xFF22C55E);  // green
const kWarning   = Color(0xFFFFBE0B);  // yellow
const kError     = Color(0xFFFF6B6B);  // red
const kInfo      = Color(0xFF4ECDC4);  // teal
const kOrange    = Color(0xFFFF9F43);  // orange

const kTextPrimary   = Colors.white;
const kTextSecondary = Color(0xFF9E9EBE);
const kTextMuted     = Color(0xFF6B6B8A);

// ── ThemeData ─────────────────────────────────────────────────────────────────
ThemeData buildTheme() => ThemeData(
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
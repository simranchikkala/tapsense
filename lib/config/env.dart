/// Build-time configuration for TapSense.
///
/// Values come from `--dart-define-from-file=env.json` (env.json is git-ignored;
/// commit env.example.json instead). Nothing secret lives in source code.
///
///   flutter run --dart-define-from-file=env.json
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Gemini key for voice parsing (ai_service.dart).
  /// Long-term: move Gemini calls to a Supabase Edge Function so the key
  /// never ships inside the app.
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// Gemini model name. Google retires models regularly — if AI features stop
  /// working, check ai.google.dev/models and set GEMINI_MODEL in env.json.
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  /// Shows the "Debug log" entry in Settings even in release/TestFlight builds.
  static const bool debugMenu = bool.fromEnvironment('DEBUG_MENU');

  /// Names of required values that are missing (empty list = all good).
  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}
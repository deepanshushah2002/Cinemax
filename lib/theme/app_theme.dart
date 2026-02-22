import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Brand colours ──────────────────────────────────────────────────────────
  static const Color accent      = Color(0xFF00E5FF); // cyan
  static const Color accentBlue  = Color(0xFF0055FF);
  static const Color purple      = Color(0xFF7B61FF);
  static const Color error       = Color(0xFFFF6B6B);
  static const Color warning     = Color(0xFFFFBE0B);
  static const Color success     = Color(0xFF00E5A0);

  // ── Background layers ──────────────────────────────────────────────────────
  static const Color bg          = Color(0xFF060810); // deepest
  static const Color bgCard      = Color(0xFF0A0C12);
  static const Color bgElevated  = Color(0xFF111520);
  static const Color surface     = Color(0xFF1E2540);
  static const Color surfaceHigh = Color(0xFF3D4A6B);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF7B8BAB);
  static const Color textMuted     = Color(0xFF3D4A6B);

  // ── Theme ──────────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: purple,
      surface: bgElevated,
      error: error,
    ),
    useMaterial3: true,
  );
}
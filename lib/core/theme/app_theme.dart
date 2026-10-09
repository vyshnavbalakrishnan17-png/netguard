import 'package:flutter/material.dart';

class NG {
  static const bg = Color(0xFF0B1220), card = Color(0xFF131C2E), line = Color(0xFF1F2B44);
  static const green = Color(0xFF2ECC71), red = Color(0xFFFF5252), orange = Color(0xFFFFA726), blue = Color(0xFF4DA3FF);
}

ThemeData ngTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: NG.blue, brightness: Brightness.dark, surface: NG.card),
      scaffoldBackgroundColor: NG.bg,
      appBarTheme: const AppBarTheme(backgroundColor: NG.bg, elevation: 0),
      navigationBarTheme: const NavigationBarThemeData(backgroundColor: NG.card),
    );

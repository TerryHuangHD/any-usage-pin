import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'core.dart';
import 'ui/dashboard.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = UsageController();
  runApp(UsageApp(controller: controller));
  unawaited(controller.initialize(open: arguments.contains('--show')));
}

class UsageApp extends StatelessWidget {
  const UsageApp({super.key, required this.controller});
  final UsageController controller;

  static final _lightTheme = _theme(Brightness.light);
  static final _darkTheme = _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF168575),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Helvetica Neue',
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.compact,
      textTheme: TextTheme(
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: scheme.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        labelSmall: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: TextStyle(
          fontFamily: 'Helvetica Neue',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'AnyUsagePin',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: switch (controller.preferences.theme) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      },
      home: Scaffold(
        body: SafeArea(child: Dashboard(controller: controller)),
      ),
    ),
  );
}

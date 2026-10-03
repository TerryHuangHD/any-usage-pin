import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';
import 'core.dart';
import 'ui/settings.dart';

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
    final dark = brightness == Brightness.dark;
    final accent = Color(dark ? 0xFF0A84FF : 0xFF007AFF);
    final text = Color(dark ? 0xFFF5F5F7 : 0xFF202124);
    final secondary = Color(dark ? 0xFFB8B8BE : 0xFF626269);
    final surface = Color(dark ? 0xFF222222 : 0xFFFFFFFF);
    final border = (dark ? Colors.white : Colors.black).withValues(
      alpha: dark ? .10 : .08,
    );
    final control = (dark ? Colors.white : Colors.black).withValues(
      alpha: dark ? .06 : .04,
    );
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      error: Color(dark ? 0xFFFF6961 : 0xFFBA1A1A),
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: secondary,
      outline: secondary.withValues(alpha: .35),
      outlineVariant: border,
      surfaceContainerLowest: surface.withValues(alpha: dark ? .90 : .82),
      surfaceContainerLow: surface,
      surfaceContainer: control,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: surface,
      surfaceTint: Colors.transparent,
      primaryContainer: accent.withValues(alpha: .12),
      onPrimaryContainer: text,
      secondaryContainer: control,
      onSecondaryContainer: text,
      tertiary: accent,
      onTertiary: Colors.white,
      tertiaryContainer: control,
      onTertiaryContainer: text,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: border),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: '.AppleSystemUIFont',
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      cardColor: scheme.surfaceContainerLowest,
      shadowColor: Colors.black.withValues(alpha: .15),
      disabledColor: secondary.withValues(alpha: .45),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        bodyLarge: TextStyle(fontSize: 13, height: 1.35, color: text),
        bodyMedium: TextStyle(fontSize: 13, height: 1.35, color: text),
        bodySmall: TextStyle(fontSize: 11, height: 1.35, color: secondary),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        labelMedium: TextStyle(fontSize: 11, color: secondary),
        labelSmall: TextStyle(fontSize: 10, color: secondary),
      ),
      iconTheme: IconThemeData(color: secondary, size: 18),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: control,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: accent),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: TextStyle(fontSize: 12, color: secondary),
        hintStyle: TextStyle(fontSize: 13, color: secondary),
        helperStyle: TextStyle(fontSize: 11, color: secondary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: shape,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: control,
          foregroundColor: text,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: shape,
          minimumSize: const Size(0, 32),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          backgroundColor: control,
          side: BorderSide(color: border),
          shape: shape,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: shape,
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: secondary, shape: shape),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(fontSize: 13, color: text),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(fontSize: 13, color: text),
        shape: shape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        contentTextStyle: TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontSize: 13,
          height: 1.35,
          color: text,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? secondary : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? control
              : states.contains(WidgetState.selected)
              ? accent
              : secondary.withValues(alpha: .35),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? states.contains(WidgetState.disabled)
                    ? secondary
                    : accent
              : control,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: secondary.withValues(alpha: .6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(secondary.withValues(alpha: .35)),
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(3),
        crossAxisMargin: 3,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 10,
            ),
          ],
        ),
        textStyle: TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontSize: 11,
          color: text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: .25),
        selectionHandleColor: accent,
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
      home: SettingsPage(controller: controller),
    ),
  );
}

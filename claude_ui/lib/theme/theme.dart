import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

class AppTheme {
  static const _seedColor = Color(0xFF4C7DF2);

  static ThemeData buildTheme(Brightness brightness, [ColorScheme? dynamicScheme]) {
    // Use a simpler black/white theme for better contrast
    final ColorScheme scheme;
    
    if (brightness == Brightness.light) {
      // Light theme - white background with dark text
      scheme = dynamicScheme ?? const ColorScheme.light(
        brightness: Brightness.light,
        primary: Color(0xFF4C7DF2),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFE3F2FD),
        onPrimaryContainer: Color(0xFF0D47A1),
        secondary: Color(0xFF616161),
        onSecondary: Colors.white,
        error: Color(0xFFD32F2F),
        onError: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black87,
        surfaceContainerLow: Color(0xFFF5F5F5),
        surfaceContainerHighest: Color(0xFFE0E0E0),
        outline: Color(0xFFBDBDBD),
        outlineVariant: Color(0xFFE0E0E0),
      );
    } else {
      // Dark theme - black background with white text
      scheme = dynamicScheme ?? const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: Color(0xFF90CAF9),
        onPrimary: Color(0xFF003258),
        primaryContainer: Color(0xFF1E3A5F),
        onPrimaryContainer: Color(0xFFBBDEFB),
        secondary: Color(0xFFB0BEC5),
        onSecondary: Color(0xFF263238),
        error: Color(0xFFEF5350),
        onError: Color(0xFF690000),
        surface: Color(0xFF121212),
        onSurface: Colors.white,
        surfaceContainerLow: Color(0xFF1E1E1E),
        surfaceContainerHighest: Color(0xFF333333),
        outline: Color(0xFF757575),
        outlineVariant: Color(0xFF424242),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      
      // Typography
      fontFamily: 'Inter',
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: Tokens.text2xl, fontWeight: FontWeight.w600),
        displayMedium: TextStyle(fontSize: Tokens.textXl, fontWeight: FontWeight.w600),
        displaySmall: TextStyle(fontSize: Tokens.textLg, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: Tokens.textMd, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: Tokens.textMd, fontWeight: FontWeight.w500),
        titleMedium: TextStyle(fontSize: Tokens.textSm, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(fontSize: Tokens.textXs, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontSize: Tokens.textMd),
        bodyMedium: TextStyle(fontSize: Tokens.textSm),
        bodySmall: TextStyle(fontSize: Tokens.textXs),
        labelLarge: TextStyle(fontSize: Tokens.textSm, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(fontSize: Tokens.textXs, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(fontSize: Tokens.textXs),
      ),

      // Components
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),

      cardTheme: CardThemeData(
        elevation: Tokens.elevationLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space5,
            vertical: Tokens.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space5,
            vertical: Tokens.space3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space3,
            vertical: Tokens.space2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: Tokens.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          borderSide: BorderSide(
            color: scheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
          borderSide: BorderSide(
            color: scheme.error,
            width: 1,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        elevation: Tokens.elevationHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusMedium),
        ),
      ),

      // Page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.macOS: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.windows: _FadeThroughPageTransitionsBuilder(),
          TargetPlatform.linux: _FadeThroughPageTransitionsBuilder(),
        },
      ),
    );
  }
}

// Custom fade through transition
class _FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation,
      child: child,
    );
  }
}
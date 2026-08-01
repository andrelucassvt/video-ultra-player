import 'package:flutter/material.dart';

const editorAccent = Color(0xff2aa79b);
const editorBackground = Color(0xffffffff);
const editorSurface = Color(0xfff5f6f8);
const editorSurfaceHigh = Color(0xffeceef1);
const editorLine = Color(0xffd9dde3);
const editorTextMuted = Color(0xff6b7280);
const editorText = Color(0xff1f2430);

final ThemeData editorTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: editorAccent,
    secondary: Color(0xff4c8dff),
    surface: editorSurface,
    error: Color(0xffd64545),
  ),
  scaffoldBackgroundColor: editorBackground,
  fontFamily: 'Roboto',
  iconTheme: const IconThemeData(color: editorText),
  sliderTheme: const SliderThemeData(
    activeTrackColor: editorAccent,
    thumbColor: editorAccent,
    inactiveTrackColor: editorLine,
  ),
  textTheme: const TextTheme(
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: editorText,
    ),
    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: editorText,
    ),
    bodyMedium: TextStyle(fontSize: 13, color: Color(0xff3a4150)),
    bodySmall: TextStyle(fontSize: 12, color: editorTextMuted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: editorAccent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: editorText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: editorText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
);

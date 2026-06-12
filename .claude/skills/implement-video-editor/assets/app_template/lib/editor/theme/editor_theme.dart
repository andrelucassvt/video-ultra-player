import 'package:flutter/material.dart';

const editorAccent = Color(0xfff5c518);
const editorBackground = Color(0xff08090c);
const editorSurface = Color(0xff12141a);
const editorSurfaceHigh = Color(0xff1b1f27);
const editorLine = Color(0xff2d3340);
const editorTextMuted = Color(0xff9aa3af);

final ThemeData editorTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: editorAccent,
    secondary: Color(0xff64d2ff),
    surface: editorSurface,
    error: Color(0xffff6b6b),
  ),
  scaffoldBackgroundColor: editorBackground,
  fontFamily: 'Roboto',
  iconTheme: const IconThemeData(color: Colors.white),
  textTheme: const TextTheme(
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
    bodyMedium: TextStyle(fontSize: 13, color: Color(0xffd4d8de)),
    bodySmall: TextStyle(fontSize: 12, color: editorTextMuted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: editorAccent,
      foregroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
);

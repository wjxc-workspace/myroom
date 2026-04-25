import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bg = Color(0xFFF4EFE6);
  static const surface = Color(0xFFFDFAF6);
  static const card = Color(0xFFFFFFFF);
  static const sage = Color(0xFF7B9E87);
  static const amber = Color(0xFFC5956A);
  static const blue = Color(0xFF8B9EC5);
  static const rose = Color(0xFFC57A8A);
  static const dark = Color(0xFF2A221A);
  static const muted = Color(0xFF9A8A7E);
  static const border = Color(0xFFEAE4D8);
  static const outerBg = Color(0xFFDDD7CC);

  // color-mix(in srgb, color N%, base) equivalent
  static Color mix(Color color, Color base, double fraction) =>
      Color.lerp(base, color, fraction)!;

  // color.withOpacity tint helper
  static Color tint(Color color, double opacity) => color.withOpacity(opacity);
}

class AppText {
  static TextStyle display({
    double size = 34,
    FontWeight weight = FontWeight.w500,
    bool italic = false,
    Color? color,
  }) =>
      GoogleFonts.cormorantGaramond(
        fontSize: size,
        fontWeight: weight,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color ?? AppColors.dark,
        height: 1.05,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.dark,
        height: height,
      );

  static TextStyle label({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.muted,
        letterSpacing: letterSpacing,
      );

  static TextStyle caption({
    double size = 10,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
  }) =>
      GoogleFonts.dmSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.muted,
        letterSpacing: letterSpacing,
      );
}

// Standard box shadow used for cards
const kCardShadow = BoxShadow(
  color: Color(0x0E000000),
  blurRadius: 10,
  offset: Offset(0, 2),
);

// Small button shadow
const kBtnShadow = BoxShadow(
  color: Color(0x18000000),
  blurRadius: 8,
  offset: Offset(0, 2),
);

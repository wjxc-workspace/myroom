import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// Shared note-category icon / palette constants, used by the notes page and the
// note composer sheet (inline category creation).

const kNoteIconMap = {
  'tag': LucideIcons.tag,
  'star': LucideIcons.star,
  'pencil': LucideIcons.pencil,
  'fileText': LucideIcons.fileText,
  'bookOpen': LucideIcons.bookOpen,
  'music': LucideIcons.music,
  'heart': LucideIcons.heart,
};

const kNoteIconKeys = [
  'tag',
  'star',
  'pencil',
  'fileText',
  'bookOpen',
  'music',
  'heart',
];

const kNoteCatPalette = [
  Color(0xFFBFA97A),
  Color(0xFFBF7A8E),
  Color(0xFF7A8EBF),
  Color(0xFF9E9E9E),
  Color(0xFF7BAF8A),
];

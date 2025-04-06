import 'package:flutter/material.dart';

// Define the color constants
const Color color1 = Color(0xFF1E3A8A); // Deep blue - Primary Variant / Dark Accent
const Color color2 = Color(0xFF3B82F6); // Vibrant blue - Primary Color
const Color color3 = Color(0xFF93C5FD); // Light blue - Secondary Background / Tints
const Color color4 = Color(0xFFA78BFA); // Soft purple - Border & Label Color
const Color color5 = Color(0xFFEEE9FF); // Very light purple - Surface / Very Subtle Background

// Define the custom ThemeData
ThemeData appTheme() {
  return ThemeData(
    // Primary colors
    primaryColor: color2, // Primary color for interactive elements
    primaryColorDark: color1, // Dark accent for AppBar, BottomNav, etc.

    // Backgrounds
    scaffoldBackgroundColor: color5, // App background
    cardColor: color3, // Card and container background

    // AppBar
    appBarTheme: const AppBarTheme(
      backgroundColor: color1, // Deep blue for AppBar
      foregroundColor: Colors.white, // White for title and icons
      elevation: 4,
    ),

    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: color2, // Vibrant blue for primary buttons
        foregroundColor: Colors.white, // White text/icons on buttons
        disabledBackgroundColor: color5, // Very light purple for disabled state
        disabledForegroundColor: color4, // Soft purple for disabled text/icons
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: color2, // Vibrant blue for text
        side: const BorderSide(color: color2), // Vibrant blue border
      ),
    ),

    // Text Fields / Inputs
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: color5, // Very light purple background
      border: OutlineInputBorder(
        borderSide: BorderSide(color: color4), // Soft purple default border
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: color4), // Soft purple default border
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: color2), // Vibrant blue focused border
      ),
      labelStyle: TextStyle(color: color4), // Soft purple for labels/placeholders
      hintStyle: TextStyle(color: color4), // Soft purple for hints
    ),

    // Text Theme
    textTheme: const TextTheme(
      headlineMedium: TextStyle(color: color2), // Titles/headings in vibrant blue
      bodyMedium: TextStyle(color: color1), // Body text in deep blue
      bodySmall: TextStyle(color: color4), // Subtle text (notes, placeholders) in soft purple
    ),

    // Icons
    iconTheme: const IconThemeData(
      color: color2, // Vibrant blue for active icons
    ),
    disabledColor: color4, // Soft purple for inactive icons

    // Checkboxes, Switches, Sliders
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return color2; // Vibrant blue when checked
        }
        return color4; // Soft purple when unchecked
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return color2; // Vibrant blue when active
        }
        return color4; // Soft purple when inactive
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return color2.withOpacity(0.5); // Lighter vibrant blue track
        }
        return color4.withOpacity(0.5); // Lighter soft purple track
      }),
    ),

    // Bottom Navigation Bar
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: color1, // Deep blue background
      selectedItemColor: color2, // Vibrant blue for selected items
      unselectedItemColor: color4, // Soft purple for unselected items
    ),

    // SnackBar
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: color1, // Deep blue background
      contentTextStyle: TextStyle(color: Colors.white), // White text
      actionTextColor: color2, // Vibrant blue for action text
    ),

    // Scrollbar
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(color2), // Vibrant blue thumb
    ),
  );
}
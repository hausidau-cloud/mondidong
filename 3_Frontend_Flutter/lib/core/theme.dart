import 'package:flutter/material.dart';
//Chức năng: Định nghĩa toàn bộ phong cách thẩm mỹ của ứng dụng (Dark Theme hiện đại):
// Màu sắc các cảm biến:
// 🔵 Nhiệt độ KK (Xanh dương)
// 🟣 Độ ẩm (Tím)
// 🟢 Điểm sương (Xanh mòng két)
// 🟠 Nhiệt độ nước (Cam)
// 🟡 Quang trở (Vàng)
// Cấu hình phông chữ, độ bo tròn của thẻ (Card), ô nhập mật khẩu, nút bấm, thanh điều hướng...
/// Bang mau dung chung toan app (dong bo voi dashboard web)
class AppColors {
  static const bg = Color(0xFF080C11);
  static const surface = Color(0xFF0F151D);
  static const surface2 = Color(0xFF141C26);
  static const surface3 = Color(0xFF1A2430);
  static const border = Color(0x1A94B2D2);
  static const borderStrong = Color(0x2E94B2D2);
  static const text = Color(0xFFE7EEF6);
  static const text2 = Color(0xFFA9B7C7);
  static const muted = Color(0xFF6F7F92);

  static const accent = Color(0xFF38BDF8);

  // Mau du lieu cam bien
  static const air = Color(0xFF38BDF8); // SHT30 nhiet do
  static const hum = Color(0xFFA78BFA); // SHT30 do am
  static const dew = Color(0xFF2DD4BF); // diem suong
  static const probe = Color(0xFFFB923C); // DS18B20

  // Mau trang thai
  static const ok = Color(0xFF22C55E);
  static const warn = Color(0xFFFACC15);
  static const danger = Color(0xFFF43F5E);
  static const off = Color(0xFF64748B);
}

const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: const Color(0xFF04131D),
    secondary: AppColors.dew,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
  );

  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text, letterSpacing: -0.3),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: ob(AppColors.borderStrong),
      enabledBorder: ob(AppColors.borderStrong),
      focusedBorder: ob(AppColors.accent, 1.6),
      errorBorder: ob(AppColors.danger),
      labelStyle: const TextStyle(color: AppColors.text2),
      hintStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.borderStrong)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.text,
      side: const BorderSide(color: AppColors.borderStrong),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: AppColors.text2, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: AppColors.bg, fontWeight: FontWeight.w700),
      showCheckmark: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.16),
      selectedIconTheme: const IconThemeData(color: AppColors.accent),
      unselectedIconTheme: const IconThemeData(color: AppColors.muted),
      selectedLabelTextStyle: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelTextStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.accent,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      tabAlignment: TabAlignment.start,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface3,
      contentTextStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.text2),
    ),
  );
}

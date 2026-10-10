import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The app's visual language.
///
/// Modelled on HubSpot's mobile app, because that is the bar this has to meet:
/// a broker who has seen a real CRM should not feel they have downgraded. That
/// means white cards with a one-pixel edge on a very pale blue-grey page, dark
/// navy for everything that is text, one teal for everything that is a link or
/// a live tab, and orange kept for the single most important action on a page.
///
/// Flat, not glassy. The previous palette leaned on translucency and soft
/// periwinkle; this one gets its structure from edges and white, which is what
/// makes a dense screen of rows readable and what every serious CRM does.
///
/// The names are unchanged from the palette before it on purpose — every screen
/// in the app refers to `AppColors.ink`, `.card`, `.glass` and the rest, so the
/// whole app re-skins from this file rather than from thirty edited screens.
class AppColors {
  /// Primary text and dark fills. HubSpot calls this Oxford; it is a navy dark
  /// enough to read as black in a paragraph and blue enough not to be harsh.
  static const ink = Color(0xFF33475B);
  static const inkSoft = Color(0xFF425B76);

  /// Secondary text, captions, inactive icons.
  static const inkMuted = Color(0xFF516F90);

  /// The page: white with the faintest blue in it, so white cards lift off it.
  static const canvas = Color(0xFFF5F8FA);

  /// Cards. Plain white, always with an edge — that edge is the whole design.
  static const card = Color(0xFFFFFFFF);
  static const cardHigh = Color(0xFFFFFFFF);

  /// Dividers inside a card, and the card edge itself.
  static const hairline = Color(0xFFDFE3EB);

  /// The accent: teal. Links, the active tab, the underline, the selected nav
  /// item. Never a large fill — HubSpot uses it as ink, not as paint.
  static const accent = Color(0xFF00A4BD);
  static const accentDark = Color(0xFF0091AE);
  static const accentSoft = Color(0xFFE5F5F8);

  /// The one loud colour, for the single most important action on a page and
  /// nothing else. Two per screen and it stops meaning anything.
  static const action = Color(0xFFFF7A59);
  static const actionDark = Color(0xFFFF5C35);
  static const actionSoft = Color(0xFFFFEDE8);

  /// A finished or disabled thing.
  static const muted = Color(0xFFCBD6E2);

  /// Surfaces that used to be translucent. Kept as names so the screens that
  /// ask for glass keep working — they now get white and a hairline, which is
  /// what this design uses in the same places.
  static const glass = Color(0xFFFFFFFF);
  static const glassSoft = Color(0xFFF5F8FA);
  static const glassCanvas = Color(0xFFFFFFFF);
  static const glassInk = Color(0xF033475B);
  static const glassEdge = Color(0xFFDFE3EB);
  static const glassEdgeInk = Color(0x2BFFFFFF);

  /// The huge pale numerals on list rows.
  static const ghost = Color(0xFFCBD6E2);
  static const ghostOnAccent = Color(0xFF8AD5E3);

  /// On dark surfaces.
  static const onInk = Color(0xFFFFFFFF);
  static const onInkMuted = Color(0xFFB0C1D4);

  /// Something went wrong, something is fine, something is worth reading.
  static const danger = Color(0xFFD94F4F);
  static const dangerSoft = Color(0xFFFDEDED);

  static const success = Color(0xFF00BDA5);
  static const successSoft = Color(0xFFE3F7F4);

  static const info = Color(0xFF516F90);
  static const infoSoft = Color(0xFFEAF0F6);
}

/// Corner radii, in one place so cards, sheets and buttons agree.
/// Corner radii, in one place so cards, sheets and buttons agree.
///
/// Small. The previous set was 26–40 and read as a consumer app; a CRM's
/// densest screen is a list of rows, and a heavy radius on every one of them
/// wastes the corners and softens exactly the structure that has to be crisp.
///
/// [chip] is a small box, not a pill. It is named for the small inline things
/// it started on, but sixty-odd call sites across the app use it for cards,
/// tiles, avatars' frames and photo corners — setting it to a pill radius
/// turned every one of them into a lozenge, and the car shelf's cards into
/// circles. True pills ask for [full] and say so.
class AppRadius {
  static const card = 8.0;
  static const sheet = 14.0;
  static const pill = 8.0;
  static const chip = 8.0;

  /// A shape with no corners left: a filter pill, an outlined empty-state
  /// button. Anything that should read as removable or as a lozenge.
  static const full = 100.0;
}

/// Lexend: the face HubSpot's app is set in. Open apertures, a tall x-height
/// and unusually plain numerals — it was drawn for reading speed, which is what
/// a screen of names and phone numbers actually needs.
///
/// Shipped as four static weights cut from the variable original, so the app
/// carries no runtime font fetch and works with no network at all.
const _fontFamily = 'Lexend';

/// Lexend has no Ethiopic glyphs. Flutter falls back per-glyph, so Amharic in a
/// message preview renders in the platform's own font rather than as boxes — but
/// naming the fallback explicitly means it picks the right one rather than the
/// first thing that happens to have the character.
const _fontFallback = <String>[
  'Noto Sans Ethiopic',
  'Abyssinica SIL',
  'sans-serif',
];

/// One scale, used everywhere.
///
/// Settled after two overshoots. Big type read as a phone with the accessibility
/// setting turned up rather than as a designed app; these are the ordinary
/// sizes, with the weight and the spacing doing the work instead.
const _text = TextTheme(
  displaySmall: TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w400,
    letterSpacing: -1.2,
    height: 1.1,
  ),
  headlineMedium: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.8,
    height: 1.15,
  ),
  headlineSmall: TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.6,
    height: 1.2,
  ),
  titleLarge: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    height: 1.25,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    height: 1.3,
  ),
  titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
  bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
  ),
  bodySmall: TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  ),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
);

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    // Deep indigo is the action colour, exactly as in the icon. Everything
    // filled is indigo with white on it; everything tinted is paper with
    // indigo.
    primary: AppColors.ink,
    onPrimary: Colors.white,
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: AppColors.ink,
    secondary: AppColors.inkMuted,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.accentSoft,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.info,
    onTertiary: Colors.white,
    tertiaryContainer: AppColors.infoSoft,
    onTertiaryContainer: AppColors.ink,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: AppColors.dangerSoft,
    onErrorContainer: Color(0xFF6B2E20),
    surface: AppColors.card,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    surfaceContainerLowest: AppColors.cardHigh,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.canvas,
    surfaceContainerHigh: Color(0xFFE6E8F4),
    surfaceContainerHighest: Color(0xFFE0E2F0),
    outline: Color(0xFFBDC1DC),
    outlineVariant: AppColors.hairline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: AppColors.ink,
    onInverseSurface: Colors.white,
    inversePrimary: AppColors.accentSoft,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      centerTitle: false,
      iconTheme: IconThemeData(color: AppColors.ink),
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontFamily: _fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
      toolbarHeight: 56,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.card,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.glassEdge),
      ),
      clipBehavior: Clip.antiAlias,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      minVerticalPadding: 10,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      subtitleTextStyle: TextStyle(
        color: AppColors.inkMuted,
        fontFamily: _fontFamily,
        fontSize: 13,
        height: 1.4,
      ),
      iconColor: AppColors.inkMuted,
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: const BorderSide(color: AppColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
      labelStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 15),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.hairline,
        disabledForegroundColor: AppColors.inkMuted,
        minimumSize: const Size(0, 46),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 46),
        side: const BorderSide(color: AppColors.muted),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentDark,
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.action,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      extendedTextStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      extendedSizeConstraints: const BoxConstraints.tightFor(height: 54),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    ),

    chipTheme: ChipThemeData(
      showCheckmark: false,
      backgroundColor: AppColors.card,
      selectedColor: AppColors.ink,
      side: const BorderSide(color: AppColors.accent),
      labelStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.ink,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
    ),

    // The thumb has to contrast with its own track, which the first pass got
    // wrong: an ink thumb on an ink track made a switched-on toggle a solid
    // black lozenge with no thumb visible in it at all. White thumb on ink when
    // on; white thumb on pale track with a visible outline when off, so an
    // untouched switch still reads as a switch rather than a grey pill.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.hairline;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return AppColors.canvas;
        return s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.muted;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.muted,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1.5),
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 1.4,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      titleTextStyle: const TextStyle(
        color: AppColors.ink,
        fontFamily: _fontFamily,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      contentTextStyle: const TextStyle(
        color: AppColors.inkMuted,
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 1.5,
      ),
    ),

    tabBarTheme: const TabBarThemeData(
      labelStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      // Teal label with a thick teal underline, grey when not on it, and a
      // hairline running the width of the bar under all of them — the tab row
      // on every list screen in HubSpot's app.
      labelColor: AppColors.accentDark,
      unselectedLabelColor: AppColors.inkMuted,
      indicatorColor: AppColors.accentDark,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.hairline,
    ),

    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.hairline,
      thumbColor: AppColors.accent,
      overlayColor: Colors.transparent,
      thumbShape: RoundSliderThumbShape(
        enabledThumbRadius: 8,
        elevation: 0,
        pressedElevation: 0,
      ),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      tickMarkShape: RoundSliderTickMarkShape(tickMarkRadius: 0),
      activeTickMarkColor: Colors.transparent,
      inactiveTickMarkColor: Colors.transparent,
      showValueIndicator: ShowValueIndicator.never,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
      linearTrackColor: AppColors.hairline,
      circularTrackColor: AppColors.hairline,
    ),

    textTheme: _text
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .copyWith(
          bodySmall: _text.bodySmall!.copyWith(color: AppColors.inkMuted),
          labelMedium: _text.labelMedium!.copyWith(color: AppColors.inkMuted),
          labelSmall: _text.labelSmall!.copyWith(color: AppColors.inkMuted),
        ),
  );
}

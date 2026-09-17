import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'onboarding_tour.dart';
import 'dart:convert';
import 'dart:ui' as ui;

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_theme') ?? true;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  runApp(const LucidApp());
}

class LucidApp extends StatelessWidget {
  const LucidApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Lucid - Mindful Screen Time',
          themeMode: mode,
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xFFFAF9F6), // Warm off-white / ivory, NOT pure white
            textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.light().textTheme),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFFC857), // Soft golden yellow
              onPrimary: Color(0xFF2F2F2F), // Dark charcoal on gold
              secondary: Color(0xFFEAA824), // Deeper warm gold
              surface: Color(0xFFFFFDF9), // Slightly lighter warm ivory cards
              onSurface: Color(0xFF2F2F2F), // Dark charcoal text
              outline: Color(0xFFD9D6D0), // Very light warm gray border
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFAF9F6),
              foregroundColor: Color(0xFF2F2F2F),
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF191816), // Warm deep charcoal
            textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFFC857), // Golden yellow
              onPrimary: Color(0xFF191816),
              secondary: Color(0xFFEAA824),
              surface: Color(0xFF24221F), // Warm dark surface card
              onSurface: Color(0xFFEDE8DF), // Warm ivory text
              outline: Color(0xFF383530), // Warm dark border
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF191816),
              foregroundColor: Color(0xFFEDE8DF),
              elevation: 0,
            ),
          ),
          home: const _AppEntry(),
        );
      },
    );
  }
}

// """ Entry point: decides whether to show onboarding or home """""""""""""""""

class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _needsOnboarding = false;
  bool _needsTour = false;
  late AnimationController _transCtrl;
  late Animation<double> _transAnim;

  @override
  void initState() {
    super.initState();
    _transCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    _transAnim = CurvedAnimation(
        parent: _transCtrl, curve: Curves.easeInOutCubic);
    _transCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() {});
      }
    });
    _decide();
  }

  @override
  void dispose() {
    _transCtrl.dispose();
    super.dispose();
  }

  Future<void> _decide() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_done') ?? false;
    final tourSeen = prefs.getBool('tour_done') ?? false;
    // Keep loading screen visible for 1.8s so user can admire the second loading screen
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() {
        _needsOnboarding = !seen;
        _needsTour = !tourSeen;
        _loading = false;
      });
      _transCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _SplashScreen();
    }

    final destScreen = _needsTour
        ? InteractiveTourScreen(
            onDone: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('tour_done', true);
              if (mounted) setState(() => _needsTour = false);
            })
        : (_needsOnboarding
            ? OnboardingScreen(
                hideHeader: !_transCtrl.isCompleted,
                onDone: () => setState(() => _needsOnboarding = false))
            : HomeScreen(hideHeader: !_transCtrl.isCompleted));

    if (_transCtrl.isCompleted) {
      return destScreen;
    }

    // Reuse the exact same _SplashScreen widget so there's zero jump or 3rd screen!
    return _SplashScreen(
      transAnim: _transAnim,
      destScreen: destScreen,
      needsOnboarding: _needsOnboarding,
    );
  }
}

// """ Splash / App Loading Screen """""""""""""""""""""""""""""""""""""""""""""

class _SplashScreen extends StatefulWidget {
  final Animation<double>? transAnim;
  final Widget? destScreen;
  final bool needsOnboarding;
  const _SplashScreen({
    Key? key,
    this.transAnim,
    this.destScreen,
    this.needsOnboarding = false,
  }) : super(key: key);
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transAnim = widget.transAnim;
    final topPad = MediaQuery.of(context).padding.top;
    final size = MediaQuery.of(context).size;

    // Pre-compute positions
    final startLogoSize = 140.0;
    final startLogoX = (size.width - startLogoSize) / 2;
    final startLogoY = (size.height - 280.0) / 2;
    final startTextX = (size.width - 90.0) / 2;
    final startTextY = startLogoY + startLogoSize + 32.0;

    final endLogoSize = widget.needsOnboarding ? 72.0 : 44.0;
    final endLogoX = widget.needsOnboarding
        ? (size.width - endLogoSize) / 2
        : 24.0;
    final endLogoY = widget.needsOnboarding ? (topPad + 32.0) : 24.0;
    final endTextX = widget.needsOnboarding
        ? (size.width - 240.0) / 2
        : (24.0 + 44.0 + 14.0);
    final endTextY = widget.needsOnboarding
        ? (endLogoY + endLogoSize + 24.0)
        : (24.0 + 1.0);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RepaintBoundary(
        child: AnimatedBuilder(
        animation: Listenable.merge([
          _fadeCtrl,
          if (transAnim != null) transAnim,
        ]),
        child: widget.destScreen,
        builder: (context, destChild) {
          final tVal = transAnim?.value ?? 0.0;
          final fadeVal = _fade.value;

          final logoX = ui.lerpDouble(startLogoX, endLogoX, tVal)!;
          final logoY = ui.lerpDouble(startLogoY, endLogoY, tVal)!;
          final logoSize = ui.lerpDouble(startLogoSize, endLogoSize, tVal)!;
          final radius = ui.lerpDouble(
              38.0, widget.needsOnboarding ? 20.0 : 12.0, tVal)!;
          final textX = ui.lerpDouble(startTextX, endTextX, tVal)!;
          final textY = ui.lerpDouble(startTextY, endTextY, tVal)!;
          final fontSize = ui.lerpDouble(
              32.0, widget.needsOnboarding ? 30.0 : 22.0, tVal)!;
          final bgOpacity = (1.0 - ((tVal - 0.35) / 0.65)).clamp(0.0, 1.0);

          return Stack(
            children: [
              // Destination screen (rendered directly with ZERO Opacity wrapper to prevent GPU saveLayer jank!)
              if (destChild != null && tVal > 0.0)
                destChild,

              // Warm background (fades out during transition to smoothly reveal destChild underneath)
              if (bgOpacity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Color.fromRGBO(25, 24, 22, bgOpacity)
                          : Color.fromRGBO(250, 249, 246, bgOpacity),
                    ),
                  ),
                ),

              // Subtitle + shimmer (only during loading, fades quickly)
              if (tVal < 0.25) ...[
                Positioned(
                  top: startTextY + 38.0 + 8.0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (1.0 - (tVal / 0.25)).clamp(0.0, 1.0) * fadeVal,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Mindful Screen Time',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 40),
                          _ShimmerBar(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // Logo
              Positioned(
                left: logoX,
                top: logoY,
                child: Opacity(
                  opacity: fadeVal,
                  child: Container(
                    width: logoSize,
                    height: logoSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFC857).withValues(alpha: 0.35 * (1.0 - tVal * 0.7)),
                          blurRadius: ui.lerpDouble(40.0, 14.0, tVal)!,
                          spreadRadius: ui.lerpDouble(6.0, 1.0, tVal)!,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),

              // Text "Lucid"
              Positioned(
                left: textX,
                top: textY,
                child: Opacity(
                  opacity: fadeVal,
                  child: Text(
                    widget.needsOnboarding && tVal > 0.5
                        ? 'Welcome to Lucid'
                        : 'Lucid',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: ui.lerpDouble(1.0, 1.2, tVal)!,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _ShimmerBar extends StatefulWidget {
  @override
  State<_ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<_ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Container(
          width: 120,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: const [
                Color(0xFFE8E5DE),
                Color(0xFFFFC857),
                Color(0xFFEAA824),
                Color(0xFFE8E5DE),
              ],
              stops: [
                (_anim.value - 0.3).clamp(0.0, 1.0),
                _anim.value.clamp(0.0, 1.0),
                (_anim.value + 0.1).clamp(0.0, 1.0),
                (_anim.value + 0.4).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

// """ Safe SharedPreferences Helper """""""""""""""""""""""""""""""""""""""""
int _safePrefsInt(SharedPreferences prefs, String key, [int fallback = 0]) {
  try {
    final val = prefs.get(key);
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? fallback;
  } catch (_) {}
  return fallback;
}

// """ Onboarding Screen (first-launch only) """""""""""""""""""""""""""""""""""

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  final bool hideHeader;
  const OnboardingScreen({Key? key, required this.onDone, this.hideHeader = false}) : super(key: key);
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _channel =
      MethodChannel('com.yuvaan.lucid/accessibility');

  late final AnimationController _bgCtrl;
  late final Animation<double> _bgAnim;
  late final AnimationController _cardCtrl;
  late final Animation<Offset> _cardAnim;
  late final Animation<double> _fadeAnim;

  bool _accessibilityGranted = false;
  bool _usageGranted = false;
  bool _batteryGranted = false;
  bool _autostartGranted = false;
  bool _notificationGranted = true;
  int _warningMins = 15;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeOut);

    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _cardAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeIn);

    // Delay onboarding animations until after the startup logo transition finishes
    // so there are zero competing animations on the GPU!
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _bgCtrl.forward();
        _cardCtrl.forward();
      }
    });

    _checkPermissions();
    _loadWarningMins();
  }

  Future<void> _loadWarningMins() async {
    final prefs = await SharedPreferences.getInstance();
    int mins = _safePrefsInt(prefs, 'warning_interval_mins', 15);
    try {
      final nativeMins = await _channel.invokeMethod<int>('getWarningInterval');
      if (nativeMins != null && nativeMins > 0) mins = nativeMins;
    } catch (_) {}
    if (mounted) setState(() => _warningMins = mins);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    bool usageOk = false;
    try {
      usageOk = await _channel.invokeMethod<bool>('isUsageAccessEnabled') ?? false;
    } catch (_) {}

    bool accessOk = false;
    try {
      accessOk =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {}

    bool batteryOk = false;
    try {
      batteryOk =
          await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? false;
    } catch (_) {}

    bool notifOk = true;
    try {
      notifOk =
          await _channel.invokeMethod<bool>('isNotificationPermissionGranted') ?? true;
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final autostartOk = prefs.getBool('autostart_granted') ?? false;

    if (mounted) {
      setState(() {
        _usageGranted = usageOk;
        _accessibilityGranted = accessOk;
        _batteryGranted = batteryOk;
        _autostartGranted = autostartOk;
        _notificationGranted = notifOk;
      });
    }
  }

  Future<void> _openAccessibility() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening Accessibility Settings... Please enable Lucid!');
    }
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openAppInfo() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening App Info... Tap the 3 dots (⋮) in top right to allow restricted settings!');
    }
    try {
      await _channel.invokeMethod('openAppInfo');
    } catch (_) {}
  }

  Future<void> _openUsageAccess() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening Usage Access Settings... Please grant access!');
    }
    try {
      await _channel.invokeMethod('openUsageAccess');
    } on PlatformException {
      // Fallback: try opening settings directly via Intent
      try {
        await _channel.invokeMethod('openSettings');
      } catch (_) {}
    }
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _requestBatteryOptimization() async {
    if (mounted) {
      _showBeautifulToast(context, 'Requesting Unrestricted Battery optimization...');
    }
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 1));
    await _checkPermissions();
  }

  Future<void> _openAutostart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autostart_granted', true);
    if (mounted) {
      setState(() => _autostartGranted = true);
      _showBeautifulToast(context, 'Opening Background Settings... Marked active!');
    }
    try {
      await _channel.invokeMethod('openAutostartSettings');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 1));
    await _checkPermissions();
  }

  Future<void> _requestNotification() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 1));
    await _checkPermissions();
  }

  Future<void> _finish() async {
    if (!_accessibilityGranted || !_usageGranted) {
      if (mounted) {
        _showBeautifulToast(context, 'Please grant both required permissions to continue!');
      }
      return;
    }
    try {
      if (!_batteryGranted) {
        await _channel.invokeMethod('requestIgnoreBatteryOptimization');
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bothGranted = _accessibilityGranted && _usageGranted;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Animated warm background
          FadeTransition(
            opacity: _bgAnim,
            child: Container(
              width: size.width,
              height: size.height,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.4,
                  colors: [
                    isDark ? const Color(0xFF24221F) : const Color(0xFFFFFDF9),
                    Theme.of(context).scaffoldBackgroundColor,
                    isDark ? const Color(0xFF191816) : const Color(0xFFFAF9F6),
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),

          // Subtle warm decorative orbs
          Positioned(
            top: -60,
            left: -80,
            child: _Orb(color: const Color(0xFFFFC857).withValues(alpha: isDark ? 0.08 : 0.12), size: 260),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: _Orb(color: const Color(0xFFEAA824).withValues(alpha: isDark ? 0.06 : 0.09), size: 220),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: SlideTransition(
                position: _cardAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo
                      Opacity(
                        opacity: widget.hideHeader ? 0.0 : 1.0,
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFC857).withValues(alpha: 0.35),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  )
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Welcome to Lucid',
                              style: GoogleFonts.dmSerifDisplay(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Set up required permissions and background defense so Lucid can guard your attention seamlessly.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),

                      // Section: Core Permissions
                      const _SectionHeader(title: 'CORE PERMISSIONS', icon: Icons.lock_outline_rounded),
                      const SizedBox(height: 12),

                      // Permission card 1: Accessibility
                      _PermissionCard(
                        title: 'Accessibility Service',
                        description:
                            'Lets Lucid detect when you open a monitored app and show the mindful timer pause. '
                            'On Android 13+, allow restricted settings in App Info if prompted.',
                        granted: _accessibilityGranted,
                        onGrant: _openAccessibility,
                        grantLabel: 'Enable in Settings',
                        icon: Icons.accessibility_new_rounded,
                        badge: 'Required',
                      ),
                      if (!_accessibilityGranted)
                        _RestrictedSettingGuide(
                          onOpenAppInfo: _openAppInfo,
                        ),
                      const SizedBox(height: 14),

                      // Permission card 2: Usage Access
                      _PermissionCard(
                        title: 'Usage Access',
                        description:
                            'Allows Lucid to read foreground screen time and compute mindful session duration.',
                        granted: _usageGranted,
                        onGrant: _openUsageAccess,
                        grantLabel: 'Grant Access',
                        icon: Icons.insights_rounded,
                        badge: 'Required',
                      ),
                      const SizedBox(height: 24),

                      // Section: Background Shield
                      const _SectionHeader(title: 'BACKGROUND DEFENSE', icon: Icons.shield_outlined),
                      const SizedBox(height: 12),

                      // Permission card 3: Battery Optimization
                      _PermissionCard(
                        title: 'Unrestricted Battery',
                        description:
                            'Exempts Lucid from aggressive battery optimization so your timer doesn\'t freeze or drop in background.',
                        granted: _batteryGranted,
                        onGrant: _requestBatteryOptimization,
                        grantLabel: 'Allow Unrestricted',
                        icon: Icons.battery_charging_full_rounded,
                        badge: 'Essential',
                      ),
                      const SizedBox(height: 14),

                      // Permission card 4: Autostart & Universal Background
                      _PermissionCard(
                        title: 'Autostart & Background Protection',
                        description:
                            'Enable Autostart and set Battery Saver to "No restrictions" (or "Unrestricted") so Lucid stays active in the background.',
                        granted: _autostartGranted,
                        onGrant: _openAutostart,
                        grantLabel: 'Configure Background Run',
                        icon: Icons.rocket_launch_rounded,
                        badge: 'Recommended',
                      ),
                      const SizedBox(height: 14),

                      // Permission card 5: Notifications (Android 13+)
                      _PermissionCard(
                        title: 'Notification Shield',
                        description:
                            'Allows the persistent foreground notification that shields Lucid from being killed by the OS.',
                        granted: _notificationGranted,
                        onGrant: _requestNotification,
                        grantLabel: 'Enable Notifications',
                        icon: Icons.notifications_active_rounded,
                        badge: 'Android 13+',
                      ),
                      const SizedBox(height: 24),
                      // Step 3: Set Warning Timer Interval
                      _WarningTimerCard(
                        intervalMins: _warningMins,
                        onChanged: (val) async {
                          setState(() => _warningMins = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('warning_interval_mins', val);
                          try {
                            await _channel.invokeMethod('setWarningInterval', val);
                          } catch (_) {}
                          if (!mounted) return;
                          _showBeautifulToast(context, 'Warning timer set to $val min${val == 1 ? "" : "s"}!');
                        },
                      ),
                      const SizedBox(height: 36),

                      // Continue button
                      SizedBox(
                        width: double.infinity,
                        child: AnimatedOpacity(
                          opacity: bothGranted ? 1.0 : 0.45,
                          duration: const Duration(milliseconds: 300),
                          child: GestureDetector(
                            onTap: _finish,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFC857),
                                    Color(0xFFEAA824),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: bothGranted
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFFFC857)
                                              .withValues(alpha: 0.45),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        )
                                      ]
                                    : [],
                              ),
                              child: const Text(
                                'Get Started →',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2F2F2F),
                                  letterSpacing: 0.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!bothGranted) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _finish,
                          child: const Text(
                            'Skip for now',
                            style: TextStyle(
                                color: Color(0xFF6B6B6B), fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final Color color;
  final double size;
  const _Orb({required this.color, required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFEAA824)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Color(0xFFEAA824),
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onGrant;
  final String grantLabel;
  final IconData icon;
  final String? badge;

  const _PermissionCard({
    required this.title,
    required this.description,
    required this.granted,
    required this.onGrant,
    required this.grantLabel,
    this.icon = Icons.security_rounded,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeGreen = const Color(0xFF489E5F);
    final Color primaryGold = const Color(0xFFEAA824);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: granted
              ? activeGreen.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.outline,
          width: 1.2,
        ),
        boxShadow: granted
            ? [
                BoxShadow(
                  color: activeGreen.withValues(alpha: 0.1),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: granted
                  ? activeGreen.withValues(alpha: 0.15)
                  : const Color(0xFFFFC857).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Icon(
                granted ? Icons.check_circle_rounded : icon,
                size: 24,
                color: granted ? activeGreen : primaryGold,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: granted
                              ? activeGreen
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: granted
                              ? activeGreen.withValues(alpha: 0.15)
                              : const Color(0xFFFFC857).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: granted
                                ? activeGreen.withValues(alpha: 0.3)
                                : primaryGold.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: granted ? activeGreen : primaryGold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
                if (!granted) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onGrant,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFC857), Color(0xFFEAA824)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFC857).withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            grantLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2F2F2F),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_rounded, size: 13, color: Color(0xFF2F2F2F)),
                        ],
                      ),
                    ),
                  ),
                ] else if (granted) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.verified_rounded, size: 14, color: activeGreen),
                      const SizedBox(width: 4),
                      Text(
                        'Granted & Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: activeGreen,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onGrant,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: activeGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: activeGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestrictedSettingGuide extends StatefulWidget {
  final VoidCallback onOpenAppInfo;

  const _RestrictedSettingGuide({
    Key? key,
    required this.onOpenAppInfo,
  }) : super(key: key);

  @override
  State<_RestrictedSettingGuide> createState() => _RestrictedSettingGuideState();
}

class _RestrictedSettingGuideState extends State<_RestrictedSettingGuide> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryGold = Color(0xFFEAA824);
    const accentGold = Color(0xFFFFC857);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF24201A) : const Color(0xFFFFFBEF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentGold.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentGold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(Icons.lock_open_rounded, size: 18, color: primaryGold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Android 13+ Restricted Setting?',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: accentGold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Help',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'If Android blocks enabling Accessibility, tap for fix.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: primaryGold,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(
                    'When sideloading an APK, Android 13/14/15 may show "Restricted setting". To unlock it in 10 seconds:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildStep(
                    context,
                    number: '1',
                    text: 'Tap "Open App Info" button below.',
                  ),
                  const SizedBox(height: 6),
                  _buildStep(
                    context,
                    number: '2',
                    text: 'Tap the 3 vertical dots (⋮) in the top right corner.',
                  ),
                  const SizedBox(height: 6),
                  _buildStep(
                    context,
                    number: '3',
                    text: 'Select "Allow restricted settings" & verify PIN/fingerprint.',
                  ),
                  const SizedBox(height: 6),
                  _buildStep(
                    context,
                    number: '4',
                    text: 'Return here and tap "Enable in Settings" above!',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onOpenAppInfo,
                      icon: const Icon(Icons.settings_applications_rounded, size: 16),
                      label: const Text('Open App Info (Tap 3 Dots)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentGold,
                        foregroundColor: const Color(0xFF2F2F2F),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, {required String number, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: const BoxDecoration(
            color: Color(0xFFFFC857),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2F2F2F),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

// """ Home Screen """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

class HomeScreen extends StatefulWidget {
  final bool hideHeader;
  const HomeScreen({Key? key, this.hideHeader = false}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<Map<String, dynamic>> _apps = [];
  bool _appsLoading = true;
  String _searchQuery = "";
  static const MethodChannel appsChannel =
    MethodChannel('lucid/apps');
  static const _channel =
      MethodChannel('com.yuvaan.lucid/accessibility');

  bool _serviceEnabled = false;
  bool _serviceAlive = false;
  bool _batteryGranted = false;
  bool _usageGranted = false;
  bool _autostartGranted = false;
  bool _notificationGranted = true;
  int _warningMins = 15;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Delay ALL platform channel calls and app loading until after startup animation completes
    // to guarantee 60/120 FPS buttery smooth animation without ANY dropped frames or saveLayer jank!
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        _checkServiceStatus();
        _loadWarningInterval();
        _loadInstalledApps().then((_) {
          _loadSavedApps();
          _checkYesterdaySuccess();
        });
      }
    });
  }

  Future<void> _checkYesterdaySuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final lastCelebrated = prefs.getString('last_celebrated_date') ?? "";
    
    if (lastCelebrated == todayStr) return;
    
    final yesterdayStr = DateTime.now().subtract(Duration(days: 1)).toIso8601String().split('T').first;
    bool hadSuccess = false;
    
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('daily_limit_')) {
        final pkg = key.substring('daily_limit_'.length);
        final limit = _safePrefsInt(prefs, key, 0);
        if (limit > 0) {
          final usageDate = prefs.getString('usage_date_$pkg');
          final usageMs = _safePrefsInt(prefs, 'usage_total_ms_$pkg', 0);
          if (usageDate == yesterdayStr) {
             final usageMins = (usageMs / 60000).floor();
             if (usageMins <= limit) {
                hadSuccess = true;
                break;
             }
          }
        }
      }
    }
    
    if (hadSuccess) {
       await prefs.setString('last_celebrated_date', todayStr);
       if (mounted) {
          _showBeautifulToast(context, '🎉 You stayed within your limits yesterday. Great job!');
       }
    } else {
       await prefs.setString('last_celebrated_date', todayStr);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check accessibility status every time the app returns from background
    // (e.g., after the user toggles the accessibility setting)
    if (state == AppLifecycleState.resumed) {
      _checkServiceStatus();
    }
  }

  Future<void> _loadWarningInterval() async {
    final prefs = await SharedPreferences.getInstance();
    int mins = _safePrefsInt(prefs, 'warning_interval_mins', 15);
    try {
      final nativeMins = await _channel.invokeMethod<int>('getWarningInterval');
      if (nativeMins != null && nativeMins > 0) mins = nativeMins;
    } catch (_) {}
    if (mounted) setState(() => _warningMins = mins);
  }

  Future<void> _setWarningInterval(int mins) async {
    setState(() => _warningMins = mins);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('warning_interval_mins', mins);
    try {
      await _channel.invokeMethod('setWarningInterval', mins);
    } catch (_) {}
    if (mounted) {
      _showBeautifulToast(context, 'Warning timer updated to $mins min${mins == 1 ? "" : "s"}!');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedApps() async {
    final prefs = await SharedPreferences.getInstance();
    // Check if we've ever saved the app list before
    final hasSaved = prefs.containsKey('enabled_target_apps');
    if (!hasSaved) {
      // First time: persist the defaults (Instagram, YouTube, Snapchat)
      await _saveEnabledApps();
      return;
    }
    final savedJson = prefs.getString('enabled_target_apps');
    if (savedJson == null) return;
    try {
      final saved = (jsonDecode(savedJson) as List).cast<String>().toSet();
      if (mounted) {
        setState(() {
          for (var app in _apps) {
            app['enabled'] = saved.contains(app['package']);
          }
        });
        try {
          await _channel.invokeMethod('setTargetApps', saved.toList());
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _saveEnabledApps() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = _apps
        .where((a) => a['enabled'] == true)
        .map<String>((a) => a['package'] as String)
        .toList();
    await prefs.setString('enabled_target_apps', jsonEncode(enabled));
    try {
      await _channel.invokeMethod('setTargetApps', enabled);
    } catch (_) {}
  }

  Future<void> _checkServiceStatus() async {
    try {
      final isEnabled =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
      final isAlive =
          await _channel.invokeMethod<bool>('isServiceAlive') ?? false;
      final batteryOk =
          await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored') ?? false;
      final usageOk =
          await _channel.invokeMethod<bool>('isUsageAccessEnabled') ?? false;
      final notifOk =
          await _channel.invokeMethod<bool>('isNotificationPermissionGranted') ?? true;
      final prefs = await SharedPreferences.getInstance();
      final autostartOk = prefs.getBool('autostart_granted') ?? false;
      if (mounted) {
        setState(() {
          _serviceEnabled = isEnabled;
          _serviceAlive = isAlive;
          _batteryGranted = batteryOk;
          _usageGranted = usageOk;
          _autostartGranted = autostartOk;
          _notificationGranted = notifOk;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _serviceEnabled = false;
          _serviceAlive = false;
        });
      }
    }
  }

  void _showPermissionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                )
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC857).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.shield_rounded, color: Color(0xFFEAA824), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'System Permissions & Shield',
                                style: GoogleFonts.dmSerifDisplay(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                'Manage privileges protecting Lucid from system killers',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionHeader(title: 'CORE ENGINE', icon: Icons.lock_outline_rounded),
                          const SizedBox(height: 12),
                          _PermissionCard(
                            title: 'Accessibility Service',
                            description: _serviceAlive
                                ? 'Active & intercepting monitored apps.'
                                : (_serviceEnabled
                                    ? 'Enabled in Android but paused by battery cleaner. Tap to restart.'
                                    : 'Required to intercept monitored apps and display 60s pause. On Android 13+, allow restricted settings in App Info if prompted.'),
                            granted: _serviceAlive,
                            onGrant: () async {
                              await _openAccessibilitySettings();
                              await _checkServiceStatus();
                              setSheetState(() {});
                            },
                            grantLabel: (_serviceEnabled && !_serviceAlive) ? 'Restart Service' : 'Enable in Settings',
                            icon: Icons.accessibility_new_rounded,
                            badge: 'Required',
                          ),
                          if (!_serviceAlive)
                            _RestrictedSettingGuide(
                              onOpenAppInfo: _openAppInfo,
                            ),
                          const SizedBox(height: 14),
                          _PermissionCard(
                            title: 'Usage Access',
                            description: 'Allows Lucid to detect foreground app state and calculate screen time.',
                            granted: _usageGranted,
                            onGrant: () async {
                              try {
                                await _channel.invokeMethod('openUsageAccess');
                              } catch (_) {}
                              await Future.delayed(const Duration(seconds: 1));
                              await _checkServiceStatus();
                              setSheetState(() {});
                            },
                            grantLabel: 'Grant Access',
                            icon: Icons.insights_rounded,
                            badge: 'Required',
                          ),
                          const SizedBox(height: 24),
                          const _SectionHeader(title: 'BACKGROUND DEFENSE', icon: Icons.shield_outlined),
                          const SizedBox(height: 12),
                          _PermissionCard(
                            title: 'Unrestricted Battery',
                            description: 'Prevents Android from killing Lucid when idle or swiped from recents.',
                            granted: _batteryGranted,
                            onGrant: () async {
                              try {
                                await _channel.invokeMethod('requestIgnoreBatteryOptimization');
                              } catch (_) {}
                              await Future.delayed(const Duration(seconds: 1));
                              await _checkServiceStatus();
                              setSheetState(() {});
                            },
                            grantLabel: 'Allow Unrestricted',
                            icon: Icons.battery_charging_full_rounded,
                            badge: 'Essential',
                          ),
                          const SizedBox(height: 14),
                          _PermissionCard(
                            title: 'Autostart & Background Protection',
                            description: 'Enable Autostart and set Battery Saver to "No restrictions" (or "Unrestricted") so Lucid stays active in the background.',
                            granted: _autostartGranted,
                            onGrant: () async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('autostart_granted', true);
                              setState(() => _autostartGranted = true);
                              setSheetState(() => _autostartGranted = true);
                              try {
                                await _channel.invokeMethod('openAutostartSettings');
                              } catch (_) {}
                            },
                            grantLabel: 'Configure Background Run',
                            icon: Icons.rocket_launch_rounded,
                            badge: 'Recommended',
                          ),
                          const SizedBox(height: 14),
                          _PermissionCard(
                            title: 'Notification Shield',
                            description: 'Ensures the foreground service notification stays visible and elevated.',
                            granted: _notificationGranted,
                            onGrant: () async {
                              try {
                                await _channel.invokeMethod('requestNotificationPermission');
                              } catch (_) {}
                              await Future.delayed(const Duration(seconds: 1));
                              await _checkServiceStatus();
                              setSheetState(() {});
                            },
                            grantLabel: 'Enable Notifications',
                            icon: Icons.notifications_active_rounded,
                            badge: 'Android 13+',
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.preview_rounded, size: 16),
                              label: const Text('Preview Onboarding / Permissions UI'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                side: BorderSide(color: const Color(0xFFEAA824).withValues(alpha: 0.5)),
                                foregroundColor: const Color(0xFFEAA824),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: const Text('Setup Preview', style: TextStyle(fontSize: 16)),
                                        leading: IconButton(
                                          icon: const Icon(Icons.arrow_back_rounded),
                                          onPressed: () => Navigator.pop(context),
                                        ),
                                      ),
                                      body: OnboardingScreen(
                                        onDone: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException catch (e) {
      debugPrint('Failed: ${e.message}');
    }
    if (mounted) {
      final msg = (_serviceEnabled && !_serviceAlive)
          ? 'Please toggle Lucid OFF then ON to restart the service!'
          : 'Opening Accessibility Settings... Please enable Lucid!';
      _showBeautifulToast(context, msg);
    }
    Future.delayed(const Duration(seconds: 2), () => _checkServiceStatus());
  }

  Future<void> _openAppInfo() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening App Info... Tap the 3 dots (⋮) in top right to allow restricted settings!');
    }
    try {
      await _channel.invokeMethod('openAppInfo');
    } catch (_) {}
  }

  Future<bool?> _showTypingPledgeDialog(String appName) {
    const pledgeText = "i choose distraction over focus";
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMatch = controller.text.trim().toLowerCase() ==
                pledgeText.toLowerCase();

            Widget buildKey(String label, {int flex = 1, Color? bg, Color? fg}) {
              return Expanded(
                flex: flex,
                child: Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Material(
                    color: bg ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setDialogState(() {
                          if (label == 'DEL') {
                            if (controller.text.isNotEmpty) {
                              controller.text = controller.text
                                  .substring(0, controller.text.length - 1);
                            }
                          } else if (label == 'Space') {
                            controller.text = '${controller.text} ';
                          } else if (label == 'Clear') {
                            controller.text = '';
                          } else {
                            controller.text = controller.text + label;
                          }
                        });
                      },
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          style: TextStyle(
                            color: fg ?? Theme.of(context).colorScheme.onSurface,
                            fontSize: label.length > 1 ? 13 : 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final row1 = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'];
            final row2 = ['j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r'];
            final row3 = ['s', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'DEL'];

            return Dialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0x80FF6B6B), width: 1.5),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Color(0x26FF6B6B),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(Icons.shield, size: 26, color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Unbind "$appName"?',
                      style: GoogleFonts.dmSerifDisplay(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'To remove focus protection, type the pledge using the mindful alphabetical keyboard:',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFC857).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        '"$pledgeText"',
                        style: const TextStyle(
                          color: Color(0xFFEAA824),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMatch
                              ? const Color(0xFF489E5F)
                              : const Color(0xFFFFC857),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        controller.text.isEmpty
                            ? 'Tap keys below to type...'
                            : controller.text,
                        style: TextStyle(
                          color: controller.text.isEmpty
                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35)
                              : Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: controller.text.isEmpty
                              ? FontWeight.normal
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // "" Custom Alphabetical Keyboard (No Glide/Autocorrect!) ""
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: row1.map((k) => buildKey(k)).toList(),
                          ),
                          Row(
                            children: row2.map((k) => buildKey(k)).toList(),
                          ),
                          Row(
                            children: row3.map((k) {
                              if (k == 'DEL') {
                                return buildKey(k,
                                    bg: const Color(0x4DCF4444),
                                    fg: const Color(0xFFFF6B6B));
                              }
                              return buildKey(k);
                            }).toList(),
                          ),
                          Row(
                            children: [
                              buildKey('Space',
                                  flex: 3, bg: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1)),
                              buildKey('Clear',
                                  flex: 1,
                                  bg: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
                                  fg: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // "" Perfectly Aligned Stacked Buttons """"""""""""""""""""""
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0xFFFFC857),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Keep Protected',
                            style: TextStyle(
                              color: Color(0xFF2F2F2F),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: isMatch
                              ? () => Navigator.of(context).pop(true)
                              : null,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: isMatch
                                ? Color(0xCCCF4444)
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Remove Protection',
                            style: TextStyle(
                              color: isMatch
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleApp(int index, bool value) async {
    final appName = _apps[index]['name'];
    if (!value) {
      // User is trying to turn off protection! Show Typing Pledge challenge!
      final confirmed = await _showTypingPledgeDialog(appName);
      if (confirmed != true) {
        return;
      }
    }

    setState(() => _apps[index]['enabled'] = value);
    await _saveEnabledApps();
    if (mounted) {
      _showBeautifulToast(context, value ? 'Added "$appName" to monitored apps' : 'Removed "$appName" from monitored apps');
    }
  }

  @override
  Widget build(BuildContext context) {
    final _ = _apps.where((a) => a['enabled'] == true).length;
    final enabledApps = _apps.where((app) {
      final name = app['name'].toString().toLowerCase();
      return app['enabled'] == true && name.contains(_searchQuery.toLowerCase());
    }).toList();
    final otherApps = _apps.where((app) {
      final name = app['name'].toString().toLowerCase();
      return app['enabled'] != true && name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
                    // "" App Bar """"""""""""""""""""""""""""""""""""""""""""""""""""
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Opacity(
                          opacity: widget.hideHeader ? 0.0 : 1.0,
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFC857).withValues(alpha: 0.35),
                                      blurRadius: 14,
                                      spreadRadius: 1,
                                    )
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Lucid',
                                      style: GoogleFonts.dmSerifDisplay(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSurface,
                                          letterSpacing: 1.2)),
                                  Text('Mindful Screen Time',
                                      style: TextStyle(
                                          fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                                ],
                              ),
                              const Spacer(),
                              IconButton(
                                icon: Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
                                tooltip: 'Permissions & System Shield',
                                onPressed: () => _showPermissionsSheet(context),
                              ),
                              IconButton(
                                icon: Icon(Icons.menu_book_rounded, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
                                tooltip: 'Open Manual',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => InteractiveTourScreen(
                                        onDone: () => Navigator.pop(context),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const _ThemeToggle(),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // "" Status Card """""""""""""""""""""""""""""""""""""""""""""""
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                        child: _StatusCard(
                          pulseAnim: _pulseAnim,
                          serviceEnabled: _serviceEnabled,
                          serviceAlive: _serviceAlive,
                          batteryGranted: _batteryGranted,
                          onActivate: _openAccessibilitySettings,
                          onManagePermissions: () => _showPermissionsSheet(context),
                          enabledApps: enabledApps.length,
                        ),
                      ),
                    ),

                    // "" Warning Timer Card """"""""""""""""""""""""""""""""""""""""
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: _WarningTimerCard(
                          intervalMins: _warningMins,
                          onChanged: _setWarningInterval,
                        ),
                      ),
                    ),

                    // "" Search Bar """"""""""""""""""""""""""""""""""""""""""""""""
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: TextField(
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Search installed apps...',
                            hintStyle: const TextStyle(color: Color(0xFF6B6B6B)),
                            prefixIcon:
                                Icon(Icons.search, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: const BorderSide(color: Color(0xFFFFC857), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        ),
                      ),
                    ),

                    // "" Enabled Target Apps Section """""""""""""""""""""""""""""""
                    if (enabledApps.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active Monitored Apps',
                                style: GoogleFonts.dmSerifDisplay(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFEAA824),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFC857).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('${enabledApps.length} active',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFEAA824))),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final app = enabledApps[index];
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                              child: _AppTile(
                                name: app['name'],
                                package: app['package'],
                                enabled: app['enabled'],
                                onChanged: (v) {
                                  final originalIndex = _apps.indexWhere(
                                    (a) => a['package'] == app['package'],
                                  );
                                  _toggleApp(originalIndex, v);
                                },
                              ),
                            );
                          },
                          childCount: enabledApps.length,
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],

                    // "" Loading indicator while apps are being fetched """"""""""
                    if (_appsLoading)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFFFFC857),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Loading installed apps...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (!_appsLoading) ...[
                    // "" Other / Available Apps Section """"""""""""""""""""""""""""
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              enabledApps.isNotEmpty ? 'Available Apps' : 'All Installed Apps',
                              style: GoogleFonts.dmSerifDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${otherApps.length} apps',
                                  style: TextStyle(
                                      fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // "" All Apps Tiles """"""""""""""""""""""""""""""""""""""""""""
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final app = otherApps[index];
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                            child: _AppTile(
                              name: app['name'],
                              package: app['package'],
                              enabled: app['enabled'],
                              onChanged: (v) {
                                final originalIndex = _apps.indexWhere(
                                  (a) => a['package'] == app['package'],
                                );
                                _toggleApp(originalIndex, v);
                              },
                            ),
                          );
                        },
                        childCount: otherApps.length,
                      ),
                    ),
                    ], // end !_appsLoading

                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
  Future<void> _loadInstalledApps() async {
    try {
      final List<dynamic> apps = await appsChannel.invokeMethod('getLauncherApps');

      setState(() {
        _apps.clear();
        for (final app in apps) {
          final package = app['package'].toString();
          if (package == 'com.yuvaan.lucid') {
            continue;
          }
          _apps.add({
            'name': app['name'],
            'package': package,
            'enabled': false,
          });
        }
        // Sort case-insensitively so apps starting with lowercase letters (like 'iMobile')
        // are properly grouped with their uppercase counterparts in alphabetical order!
        _apps.sort((a, b) => (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase()));
        _appsLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading apps: $e");
      if (mounted) setState(() => _appsLoading = false);
    }
  }
}

// """ Warning Timer Card """""""""""""""""""""""""""""""""""""""""""""""""""""""

class _WarningTimerCard extends StatefulWidget {
  final int intervalMins;
  final ValueChanged<int> onChanged;

  const _WarningTimerCard({
    required this.intervalMins,
    required this.onChanged,
  });

  @override
  State<_WarningTimerCard> createState() => _WarningTimerCardState();
}

class _WarningTimerCardState extends State<_WarningTimerCard> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.intervalMins.toString());
  }

  @override
  void didUpdateWidget(covariant _WarningTimerCard old) {
    super.didUpdateWidget(old);
    if (old.intervalMins != widget.intervalMins &&
        _ctrl.text != widget.intervalMins.toString()) {
      _ctrl.text = widget.intervalMins.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    FocusScope.of(context).unfocus();
    final val = int.tryParse(raw.trim());
    if (val != null && val >= 1 && val <= 20) {
      widget.onChanged(val);
    } else {
      _ctrl.text = widget.intervalMins.toString();
      final msg = val == null
          ? 'Please enter a number between 1 and 20'
          : val < 1
              ? 'Minimum timer is 1 minute'
              : 'Maximum timer is 20 minutes';
      _showBeautifulToast(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.timer_outlined,
                    color: Color(0xFFEAA824), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Warning Timer Interval',
                      style: GoogleFonts.dmSerifDisplay(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alert after ${widget.intervalMins} min${widget.intervalMins == 1 ? "" : "s"} in a monitored app',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. 15',
                    hintStyle: const TextStyle(color: Color(0xFF6B6B6B)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_circle, color: Color(0xFFEAA824)),
                      onPressed: () => _submit(_ctrl.text),
                      tooltip: 'Save Timer Interval',
                    ),
                    suffixText: 'mins',
                    suffixStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  onSubmitted: _submit,
                  onEditingComplete: () => _submit(_ctrl.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// """ Status Card """"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

class _StatusCard extends StatelessWidget {
  final Animation<double> pulseAnim;
  final bool serviceEnabled;
  final bool serviceAlive;
  final bool batteryGranted;
  final VoidCallback onActivate;
  final VoidCallback? onManagePermissions;
  final int enabledApps;

  const _StatusCard({
    required this.pulseAnim,
    required this.serviceEnabled,
    this.serviceAlive = true,
    this.batteryGranted = true,
    required this.onActivate,
    this.onManagePermissions,
    required this.enabledApps,
  });

  @override
  Widget build(BuildContext context) {
    final bool isZombie = serviceEnabled && !serviceAlive;
    final bool isHealthy = serviceEnabled && serviceAlive;

    final Color statusColor = isHealthy
        ? const Color(0xFF489E5F)
        : (isZombie ? const Color(0xFFFFB74D) : const Color(0xFFFF9800));

    final String statusLabel = isHealthy
        ? 'Engine Active'
        : (isZombie ? 'Engine Sleeping / Tap to Wake' : 'Setup Required');

    final String title = isHealthy
        ? 'Lucid is guarding you.'
        : (isZombie ? 'Service Needs Wake-Up' : 'Activate Lucid');

    final String subtitle = isHealthy
        ? 'Monitoring $enabledApps app${enabledApps != 1 ? "s" : ""}. '
            'A 60s mindful pause runs every time you open a monitored app.'
        : (isZombie
            ? 'Android battery optimization has paused the Lucid engine. Tap below to reactivate in Settings.'
            : 'Enable the Accessibility Service to protect target apps. (On Android 13+, allow restricted settings in App Info if prompted).');

    final String buttonLabel = isZombie
        ? 'Reactivate Service ⚡'
        : 'Enable Accessibility Service →';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedBuilder(
                  animation: pulseAnim,
                  builder: (_, __) => Transform.scale(
                    scale: isHealthy ? 1.0 : pulseAnim.value,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (onManagePermissions != null)
                  GestureDetector(
                    onTap: onManagePermissions,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC857).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined, size: 13, color: Color(0xFFEAA824)),
                          SizedBox(width: 4),
                          Text(
                            'Permissions',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEAA824),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            if (isHealthy && !batteryGranted) ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: onManagePermissions,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB74D).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFFFB74D)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Battery optimization active • Tap to exempt',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFFFB74D),
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFFFFB74D)),
                    ],
                  ),
                ),
              ),
            ],
            if (!isHealthy) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onActivate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isZombie
                        ? const Color(0xFFFFB74D)
                        : const Color(0xFFFFC857),
                    foregroundColor: const Color(0xFF2F2F2F),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isZombie
                    ? 'Tip: In Accessibility Settings, toggle Lucid OFF then ON'
                    : 'Settings → Accessibility → Downloaded Apps → Lucid',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// """ How It Works Card """"""""""""""""""""""""""""""""""""""""""""""""""""""""



// """ App Tile """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

class _AppTile extends StatefulWidget {
  final String name;
  final String package;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AppTile({
    required this.name,
    required this.package,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  bool _expanded = false;
  int _customTimer = 0;
  int _dailyLimit = 0;
  int _savedDailyLimit = 0;
  int _usageMs = 0;
  String _usageDate = "";

  @override
  void initState() {
    super.initState();
    _loadTimer();
  }

  Future<void> _loadTimer() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customTimer = _safePrefsInt(prefs, 'app_timer_${widget.package}', 0);
      _dailyLimit = _safePrefsInt(prefs, 'daily_limit_${widget.package}', 0);
      _savedDailyLimit = _dailyLimit;
      _usageMs = _safePrefsInt(prefs, 'usage_total_ms_${widget.package}', 0);
      _usageDate = prefs.getString('usage_date_${widget.package}') ?? "";
    });
  }

  Future<void> _setTimer(int val) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _customTimer = val);
    if (val == 0) {
      await prefs.remove('app_timer_${widget.package}');
    } else {
      await prefs.setInt('app_timer_${widget.package}', val);
    }
  }

  Future<void> _setDailyLimit(int val) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dailyLimit = val;
      _savedDailyLimit = val;
    });
    if (val == 0) {
      await prefs.remove('daily_limit_${widget.package}');
    } else {
      await prefs.setInt('daily_limit_${widget.package}', val);
    }
  }

  Future<void> _confirmAndSetDailyLimit(int val) async {
    // If decreasing the limit, or turning it on from no limit, save immediately
    if (val < _savedDailyLimit && val != 0 || _savedDailyLimit == 0 && val != 0) {
      await _setDailyLimit(val);
      return;
    }
    
    // If increasing limit or removing limit (val == 0), add friction
    if (val > _savedDailyLimit || val == 0) {
      bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _FrictionDialog(
          title: val == 0 ? 'Disable Daily Limit?' : 'Increase Limit to $val mins?',
          message: 'Are you sure you want to give yourself more time in this app? Take a moment to reflect.',
          waitSeconds: 30,
        ),
      );

      if (confirmed == true) {
        await _setDailyLimit(val);
      } else {
        // Revert
        setState(() {
          _dailyLimit = _savedDailyLimit;
        });
      }
    }
  }

  Color _colorFromName(String name) {
    if (name.isEmpty) return const Color(0xFFFFC857);
    final firstChar = name.trim().toUpperCase();
    if (firstChar.isEmpty) return const Color(0xFFFFC857);
    final code = firstChar.codeUnitAt(0);
    if (code >= 65 && code <= 90) {
      final index = code - 65;
      final hue = (index * (360.0 / 26.0)) % 360.0;
      return HSVColor.fromAHSV(1.0, hue, 0.65, 0.92).toColor();
    } else if (code >= 48 && code <= 57) {
      final index = code - 48;
      final hue = (180.0 + index * 15.0) % 360.0;
      return HSVColor.fromAHSV(1.0, hue, 0.65, 0.92).toColor();
    }
    return const Color(0xFFFFC857);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';
    final bgColor = _colorFromName(widget.name);

    return TweenAnimationBuilder<double>(
      key: ValueKey('${widget.package}_${widget.enabled}'),
      tween: Tween(begin: 0.93, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: AnimatedContainer(
      duration: Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.enabled
              ? const Color(0xFFFFC857).withValues(alpha: 0.4)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: widget.enabled ? () => setState(() => _expanded = !_expanded) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: bgColor.withValues(alpha: 0.4), width: 1),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: bgColor,
                  ),
                ),
              ),
            ),
            title: Text(widget.name,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            trailing: Switch(
              value: widget.enabled,
              activeThumbColor: const Color(0xFFFFC857),
              onChanged: widget.onChanged,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: (!widget.enabled || !_expanded) ? SizedBox.shrink() : Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFC857).withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Warning Timer',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _customTimer == 0 ? 'Global Default' : '$_customTimer mins',
                          style: TextStyle(color: const Color(0xFFEAA824), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFFFFC857),
                        inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                        thumbColor: Colors.white,
                        overlayColor: const Color(0xFFFFC857).withValues(alpha: 0.2),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _customTimer.toDouble(),
                        min: 0,
                        max: 20,
                        divisions: 20,
                        onChanged: (val) {
                          _setTimer(val.toInt());
                        },
                      ),
                    ),
                    Text(
                      'Drag to 0 to use the global warning timer.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Daily App Limit',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _dailyLimit == 0 ? 'No Limit' : '$_dailyLimit mins',
                          style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Color(0xFF38BDF8),
                        inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                        thumbColor: Colors.white,
                        overlayColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _dailyLimit.toDouble(),
                        min: 0,
                        max: 180,
                        divisions: 36,
                        onChanged: (val) {
                          setState(() { _dailyLimit = val.toInt(); });
                        },
                        onChangeEnd: (val) {
                          _confirmAndSetDailyLimit(val.toInt());
                        },
                      ),
                    ),
                    Text(
                      'Drag to 0 to disable daily limit.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11),
                    ),
                    if (_dailyLimit > 0) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Builder(
                          builder: (context) {
                            final todayStr = DateTime.now().toIso8601String().split('T').first;
                            final usageMins = _usageDate == todayStr ? (_usageMs / 60000).floor() : 0;
                            final remainingMins = _dailyLimit - usageMins;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    Text('Today\'s Usage', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                                    SizedBox(height: 4),
                                    Text('$usageMins min', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text('Limit', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                                    SizedBox(height: 4),
                                    Text('$_dailyLimit min', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text('Remaining', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                                    SizedBox(height: 4),
                                    Text('${remainingMins > 0 ? remainingMins : 0} min', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: remainingMins > 0 ? Color(0xFF4CAF50) : Color(0xFFFF6B6B))),
                                  ],
                                ),
                              ],
                            );
                          }
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),
          )
        ],
      ),
      ),
    );
  }
}

void _showBeautifulToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _AnimatedToast(
      message: message,
      
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _AnimatedToast extends StatefulWidget {
  final String message;
  
  final VoidCallback onDismiss;

  const _AnimatedToast({
    Key? key,
    required this.message,
    
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeIn));

    _ctrl.forward();

    Future.delayed(const Duration(seconds: 2, milliseconds: 500), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 50,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            return Transform.scale(
              scale: _scale.value,
              child: Opacity(
                opacity: _fade.value,
                child: child,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: Theme.of(context).brightness == Brightness.dark
                    ? const [Color(0xFF2A2518), Color(0xFF1B1A18)]
                    : const [Color(0xFFFFFDF9), Color(0xFFFAF9F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFC857).withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.18),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}





class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, child) {
        final isDark = mode == ThemeMode.dark;
        return GestureDetector(
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            final newTheme = isDark ? ThemeMode.light : ThemeMode.dark;
            themeNotifier.value = newTheme;
            await prefs.setBool('is_dark_theme', !isDark);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 56,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark ? const Color(0xFF24221F) : const Color(0xFFE8E5DE),
              border: Border.all(
                color: isDark ? const Color(0xFFFFC857).withValues(alpha: 0.5) : const Color(0xFFD9D6D0),
              ),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  top: 3,
                  left: isDark ? 27 : 3,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, anim) => RotationTransition(
                      turns: child.key == const ValueKey('moon') 
                          ? Tween<double>(begin: 0.5, end: 1).animate(anim)
                          : Tween<double>(begin: 0.5, end: 1).animate(anim),
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: isDark 
                        ? const Icon(Icons.nightlight_round, key: ValueKey('moon'), size: 22, color: Color(0xFFFFC857))
                        : const Icon(Icons.wb_sunny_rounded, key: ValueKey('sun'), size: 22, color: Color(0xFFEAA824)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FrictionDialog extends StatefulWidget {
  final String title;
  final String message;
  final int waitSeconds;

  const _FrictionDialog({
    Key? key,
    required this.title,
    required this.message,
    required this.waitSeconds,
  }) : super(key: key);

  @override
  State<_FrictionDialog> createState() => _FrictionDialogState();
}

class _FrictionDialogState extends State<_FrictionDialog> {
  late int _timeLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timeLeft = widget.waitSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() {
          _timeLeft--;
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canConfirm = _timeLeft == 0;
    
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.message,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8), fontSize: 15),
          ),
          const SizedBox(height: 24),
          if (!canConfirm)
            Text(
              '$_timeLeft',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFC857),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
        ),
        ElevatedButton(
          onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFC857),
            foregroundColor: const Color(0xFF2F2F2F),
            disabledBackgroundColor: const Color(0xFFFFC857).withValues(alpha: 0.2),
          ),
          child: Text('Confirm'),
        ),
      ],
    );
  }
}

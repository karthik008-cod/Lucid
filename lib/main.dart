import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:app_usage/app_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:ui' as ui;

void main() {
  runApp(const LucidApp());
}

class LucidApp extends StatelessWidget {
  const LucidApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lucid - Mindful Screen Time',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBB86FC),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1C1C2E),
        ),
      ),
      home: const _AppEntry(),
    );
  }
}

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ Entry point: decides whether to show onboarding or home Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> with SingleTickerProviderStateMixin {
  bool _loading = true;
  bool _needsOnboarding = false;
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
    // Keep loading screen visible for 1.8s so user can admire the second loading screen
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() {
        _needsOnboarding = !seen;
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

    final destScreen = _needsOnboarding
        ? OnboardingScreen(
            hideHeader: !_transCtrl.isCompleted,
            onDone: () => setState(() => _needsOnboarding = false))
        : HomeScreen(hideHeader: !_transCtrl.isCompleted);

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

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ Splash / App Loading Screen Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

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
      backgroundColor: const Color(0xFF03000D),
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

              // Dark background (fades out during transition to smoothly reveal destChild underneath)
              if (bgOpacity > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Color.fromRGBO(3, 0, 13, bgOpacity),
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
                          const Text(
                            'Mindful Screen Time',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8877AA),
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
                          color: Color.fromRGBO(187, 134, 252, 0.5 * (1.0 - tVal * 0.7)),
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
                      color: Colors.white,
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
                Color(0xFF1A0A2E),
                Color(0xFFBB86FC),
                Color(0xFF03DAC6),
                Color(0xFF1A0A2E),
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

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ Onboarding Screen (first-launch only) Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

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
    int mins = prefs.getInt('warning_interval_mins') ?? 15;
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
      final end = DateTime.now();
      await AppUsage()
          .getAppUsage(end.subtract(const Duration(seconds: 5)), end);
      usageOk = true;
    } catch (_) {}

    bool accessOk = false;
    try {
      accessOk =
          await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _usageGranted = usageOk;
        _accessibilityGranted = accessOk;
      });
    }
  }

  Future<void> _openAppInfo() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening App Info... Please allow restricted settings.', 'âš™ï¸');
    }
    try {
      await _channel.invokeMethod('openAppInfo');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openAccessibility() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening Accessibility Settings... Please enable Lucid!', '♿');
    }
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openUsageAccess() async {
    if (mounted) {
      _showBeautifulToast(context, 'Opening Usage Access Settings... Please grant access!', '📱');
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

  Future<void> _finish() async {
    if (!_accessibilityGranted || !_usageGranted) {
      if (mounted) {
        _showBeautifulToast(context, 'Please grant both permissions to continue!', 'âš ï¸');
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bothGranted = _accessibilityGranted && _usageGranted;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Animated gradient background
          FadeTransition(
            opacity: _bgAnim,
            child: Container(
              width: size.width,
              height: size.height,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.4,
                  colors: [
                    Color(0xFF1A0A2E),
                    Color(0xFF0D0D1A),
                    Color(0xFF060610)
                  ],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
          ),

          // Glowing orbs
          Positioned(
            top: -60,
            left: -80,
            child: _Orb(color: const Color(0x22BB86FC), size: 260),
          ),
          Positioned(
            bottom: -80,
            right: -60,
            child: _Orb(color: const Color(0x1403DAC6), size: 220),
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
                                    color: const Color(0xFFBB86FC).withOpacity(0.5),
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
                            const Text(
                              'Welcome to Lucid',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Three quick permissions and you\'re set.\nLucid needs these to guard your attention.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF9E9E9E),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Permission card 0: Restricted Settings
                      _PermissionCard(
                        icon: 'âš™ï¸',
                        title: 'Allow Restricted Settings',
                        description:
                            'If the Accessibility toggle is greyed out in settings, return here, tap "Open App Info", tap the top-right â‹® menu and select "Allow restricted settings". If you don\'t see it, you can skip this step!',
                        granted: _accessibilityGranted,
                        onGrant: _openAppInfo,
                        grantLabel: 'Open App Info',
                      ),
                      const SizedBox(height: 16),

                      // Permission card 1: Accessibility
                      _PermissionCard(
                        icon: '♿',
                        title: 'Accessibility Service',
                        description:
                            'Lets Lucid detect when you open a monitored app and show the mindful timer overlay.',
                        granted: _accessibilityGranted,
                        onGrant: _openAccessibility,
                        grantLabel: 'Enable in Settings',
                      ),
                      const SizedBox(height: 16),

                      // Permission card 2: Usage Access
                      _PermissionCard(
                        icon: '📱',
                        title: 'Usage Access',
                        description:
                            'Allows Lucid to read which app is in the foreground so it can track session time.',
                        granted: _usageGranted,
                        onGrant: _openUsageAccess,
                        grantLabel: 'Grant Usage Access',
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
                          if (mounted) {
                            _showBeautifulToast(context, 'Warning timer set to $val min${val == 1 ? "" : "s"}!', 'â°');
                          }
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
                                    Color(0xFFBB86FC),
                                    Color(0xFF7C4DFF)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: bothGranted
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFBB86FC)
                                              .withOpacity(0.4),
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
                                  color: Colors.white,
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
                                color: Color(0xFF616161), fontSize: 13),
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

class _PermissionCard extends StatelessWidget {
  final String icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onGrant;
  final String grantLabel;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onGrant,
    required this.grantLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF12101E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: granted
              ? const Color(0xFF4CAF50).withOpacity(0.6)
              : const Color(0xFFBB86FC).withOpacity(0.2),
          width: 1.2,
        ),
        boxShadow: granted
            ? [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.12),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: granted
                  ? const Color(0xFF4CAF50).withOpacity(0.15)
                  : const Color(0xFFBB86FC).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(granted ? '✅' : icon,
                  style: TextStyle(
                      fontSize: granted ? 24 : 22,
                      color: granted ? const Color(0xFF4CAF50) : Colors.white)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color:
                            granted ? const Color(0xFF4CAF50) : Colors.white)),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9E9E9E), height: 1.4)),
                if (!granted) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onGrant,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFBB86FC), Color(0xFF7C4DFF)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(grantLabel,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
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

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ Home Screen Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

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
        });
      }
    });
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
    int mins = prefs.getInt('warning_interval_mins') ?? 15;
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
      _showBeautifulToast(context, 'Warning timer updated to $mins min${mins == 1 ? "" : "s"}!', 'â°');
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
      if (mounted) setState(() => _serviceEnabled = isEnabled);
    } catch (_) {
      if (mounted) setState(() => _serviceEnabled = false);
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException catch (e) {
      debugPrint('Failed: ${e.message}');
    }
    if (mounted) {
      _showBeautifulToast(context, 'Opening Accessibility Settings... Please enable Lucid!', '♿');
    }
    Future.delayed(const Duration(seconds: 2), () => _checkServiceStatus());
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
                  padding: const EdgeInsets.all(2.0),
                  child: Material(
                    color: bg ?? const Color(0xFF2A2A3E),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setDialogState(() {
                          if (label == 'âŒ«') {
                            if (controller.text.isNotEmpty) {
                              controller.text = controller.text
                                  .substring(0, controller.text.length - 1);
                            }
                          } else if (label == 'Space') {
                            controller.text = controller.text + ' ';
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
                            color: fg ?? Colors.white,
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
            final row3 = ['s', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'âŒ«'];

            return Dialog(
              backgroundColor: const Color(0xFF1C1C2E),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: Color(0x80FF6B6B), width: 1.5),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Color(0x26FF6B6B),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('ðŸ§˜', style: TextStyle(fontSize: 26)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Unbind "$appName"?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'To remove focus protection, type the pledge using the mindful alphabetical keyboard:',
                      style: TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontSize: 13,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x4DBB86FC)),
                      ),
                      child: const Text(
                        '"$pledgeText"',
                        style: TextStyle(
                          color: Color(0xFFBB86FC),
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
                        color: const Color(0xFF0D0D1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMatch
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFBB86FC),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        controller.text.isEmpty
                            ? 'Tap keys below to type...'
                            : controller.text,
                        style: TextStyle(
                          color: controller.text.isEmpty
                              ? const Color(0xFF666680)
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: controller.text.isEmpty
                              ? FontWeight.normal
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Ã¢"â‚¬Ã¢"â‚¬ Custom Alphabetical Keyboard (No Glide/Autocorrect!) Ã¢"â‚¬Ã¢"â‚¬
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141422),
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
                              if (k == 'âŒ«') {
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
                                  flex: 3, bg: const Color(0xFF2A2A3E)),
                              buildKey('Clear',
                                  flex: 1,
                                  bg: const Color(0xFF3A3A52),
                                  fg: const Color(0xFFCCCCCC)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Ã¢"â‚¬Ã¢"â‚¬ Perfectly Aligned Stacked Buttons Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0x33BB86FC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Ã°Å¸"ºÂ¡Ã¯Â¸Â Keep Protected',
                            style: TextStyle(
                              color: Color(0xFFBB86FC),
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: isMatch
                                ? const Color(0xCCCF4444)
                                : const Color(0xFF2A2A3E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Remove Protection',
                            style: TextStyle(
                              color: isMatch
                                  ? Colors.white
                                  : const Color(0xFF666680),
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
      _showBeautifulToast(context, value ? 'Added "$appName" to monitored apps' : 'Removed "$appName" from monitored apps', value ? '✅' : 'âŒ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _apps.where((a) => a['enabled'] == true).length;
    final enabledApps = _apps.where((app) {
      final name = app['name'].toString().toLowerCase();
      return app['enabled'] == true && name.contains(_searchQuery.toLowerCase());
    }).toList();
    final otherApps = _apps.where((app) {
      final name = app['name'].toString().toLowerCase();
      return app['enabled'] != true && name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
                    // Ã¢"â‚¬Ã¢"â‚¬ App Bar Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
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
                                      color: const Color(0xFFBB86FC).withOpacity(0.4),
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
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Lucid',
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 1.2)),
                                  Text('Mindful Screen Time',
                                      style: TextStyle(
                                          fontSize: 12, color: Color(0xFF9E9E9E))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Ã¢"â‚¬Ã¢"â‚¬ Status Card Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                        child: _StatusCard(
                          pulseAnim: _pulseAnim,
                          serviceEnabled: _serviceEnabled,
                          onActivate: _openAccessibilitySettings,
                          enabledApps: enabledApps.length,
                        ),
                      ),
                    ),

                    // Ã¢"â‚¬Ã¢"â‚¬ Warning Timer Card Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: _WarningTimerCard(
                          intervalMins: _warningMins,
                          onChanged: _setWarningInterval,
                        ),
                      ),
                    ),

                    // Ã¢"â‚¬Ã¢"â‚¬ Search Bar Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search installed apps...',
                            hintStyle: const TextStyle(color: Color(0xFF616161)),
                            prefixIcon:
                                const Icon(Icons.search, color: Color(0xFF9E9E9E)),
                            filled: true,
                            fillColor: const Color(0xFF1C1C2E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
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

                    // Ã¢"â‚¬Ã¢"â‚¬ Enabled Target Apps Section Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    if (enabledApps.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Active Monitored Apps',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFBB86FC),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFBB86FC).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('${enabledApps.length} active',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFBB86FC))),
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

                    // Ã¢"â‚¬Ã¢"â‚¬ Loading indicator while apps are being fetched Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    if (_appsLoading)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Column(
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFFBB86FC),
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Loading installed apps...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF9E9E9E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (!_appsLoading) ...[
                    // Ã¢"â‚¬Ã¢"â‚¬ Other / Available Apps Section Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              enabledApps.isNotEmpty ? 'Available Apps' : 'All Installed Apps',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C2E),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${otherApps.length} apps',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF9E9E9E))),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Ã¢"â‚¬Ã¢"â‚¬ All Apps Tiles Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬
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
      print("Error loading apps: $e");
      if (mounted) setState(() => _appsLoading = false);
    }
  }
}

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ Warning Timer Card Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

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
    if (val != null && val > 0 && val <= 999) {
      widget.onChanged(val);
    } else {
      // revert to current value
      _ctrl.text = widget.intervalMins.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFBB86FC).withOpacity(0.3),
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
                  color: const Color(0xFFBB86FC).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.timer_outlined,
                    color: Color(0xFFBB86FC), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Warning Timer Interval',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Alert after ${widget.intervalMins} min${widget.intervalMins == 1 ? "" : "s"} in a monitored app',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9E9E9E),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. 15',
                    hintStyle: const TextStyle(color: Color(0xFF616161)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_circle, color: Color(0xFFBB86FC)),
                      onPressed: () => _submit(_ctrl.text),
                      tooltip: 'Save Timer Interval',
                    ),
                    suffixText: 'mins',
                    suffixStyle: const TextStyle(
                      color: Color(0xFF9E9E9E),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0D0D1A),
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

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ Status Card Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

class _StatusCard extends StatelessWidget {
  final Animation<double> pulseAnim;
  final bool serviceEnabled;
  final VoidCallback onActivate;
  final int enabledApps;

  const _StatusCard({
    required this.pulseAnim,
    required this.serviceEnabled,
    required this.onActivate,
    required this.enabledApps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C1C2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: serviceEnabled
              ? const Color(0xFF4CAF50).withOpacity(0.4)
              : const Color(0xFFBB86FC).withOpacity(0.3),
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
                    scale: serviceEnabled ? 1.0 : pulseAnim.value,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: serviceEnabled
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9800),
                        boxShadow: [
                          BoxShadow(
                            color: (serviceEnabled
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFFF9800))
                                .withOpacity(0.6),
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
                  serviceEnabled ? 'Engine Active' : 'Setup Required',
                  style: TextStyle(
                    fontSize: 13,
                    color: serviceEnabled
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9800),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              serviceEnabled ? 'Lucid is guarding you.' : 'Activate Lucid',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              serviceEnabled
                  ? 'Monitoring $enabledApps app${enabledApps != 1 ? "s" : ""}. '
                      'A 60s mindful pause runs every time you open a monitored app.'
                  : 'Enable the Accessibility Service so Lucid can intercept target apps.',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9E9E9E),
                height: 1.5,
              ),
            ),
            if (!serviceEnabled) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onActivate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFBB86FC),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Enable Accessibility Service →',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Settings → Accessibility → Downloaded Apps → Lucid',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E9E9E),
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

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ How It Works Card Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111122),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A3E), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How Lucid Works',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFBB86FC))),
          const SizedBox(height: 16),
          _step('Ã¢ÂÂ³', '60-Second Mindful Pause',
              'When you open a monitored app, a beautiful animated timer overlay appears. It vanishes once 60 seconds pass.'),
          const SizedBox(height: 12),
          _step('Ã°Å¸"Â', 'Session Tracking',
              'Once inside, you can freely switch tabs without interruption. The timer only re-appears if you leave and come back.'),
          const SizedBox(height: 12),
          _step('Ã¢ÂÂ°', '15-Minutes Usage Reminder',
              'After your session limit, Lucid asks if you really want to keep scrolling - or do something better.'),
        ],
      ),
    );
  }

  Widget _step(String emoji, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text(body,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9E9E9E), height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

// Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬ App Tile Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬Ã¢"â‚¬

class _AppTile extends StatelessWidget {
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

  // Generate a consistent rainbow color from the starting letter of the app name!
  Color _colorFromName(String name) {
    if (name.isEmpty) return const Color(0xFFBB86FC);
    final firstChar = name.trim().toUpperCase();
    if (firstChar.isEmpty) return const Color(0xFFBB86FC);
    final code = firstChar.codeUnitAt(0);
    // 'A' is 65, 'Z' is 90 -> map index 0..25 smoothly across the 360 degree rainbow color wheel!
    if (code >= 65 && code <= 90) {
      final index = code - 65;
      final hue = (index * (360.0 / 26.0)) % 360.0;
      return HSVColor.fromAHSV(1.0, hue, 0.75, 1.0).toColor();
    } else if (code >= 48 && code <= 57) {
      // Numbers get a nice cyan spectrum
      final index = code - 48;
      final hue = (180.0 + index * 15.0) % 360.0;
      return HSVColor.fromAHSV(1.0, hue, 0.75, 1.0).toColor();
    }
    return const Color(0xFFBB86FC);
  }

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final bgColor = _colorFromName(name);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? const Color(0xFFBB86FC).withOpacity(0.4)
              : const Color(0xFF2A2A3E),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: bgColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: bgColor.withOpacity(0.4), width: 1),
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
        title: Text(name,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
        trailing: Switch(
          value: enabled,
          activeColor: const Color(0xFFBB86FC),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

void _showBeautifulToast(BuildContext context, String message, String icon) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _AnimatedToast(
      message: message,
      icon: icon,
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _AnimatedToast extends StatefulWidget {
  final String message;
  final String icon;
  final VoidCallback onDismiss;

  const _AnimatedToast({
    Key? key,
    required this.message,
    required this.icon,
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
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1040), Color(0xFF160824)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFBB86FC).withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFBB86FC).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBB86FC).withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(widget.icon, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      color: Colors.white,
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





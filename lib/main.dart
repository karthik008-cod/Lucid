import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'package:app_usage/app_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:installed_apps/installed_apps.dart';

void main() {
  runApp(const LucidApp());
}

class LucidApp extends StatelessWidget {
  const LucidApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lucid – Mindful Screen Time',
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

// ─── Entry point: decides whether to show onboarding or home ─────────────────

class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool _loading = true;
  bool _needsOnboarding = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_done') ?? false;
    setState(() {
      _needsOnboarding = !seen;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _SplashScreen();
    }
    if (_needsOnboarding) {
      return OnboardingScreen(
          onDone: () => setState(() => _needsOnboarding = false));
    }
    return const HomeScreen();
  }
}

// ─── Splash / App Loading Screen ─────────────────────────────────────────────

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbCtrl;
  late final AnimationController _rotCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _orb;
  late final Animation<double> _rot;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _orbCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _rotCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 8))
          ..repeat();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();

    _orb = Tween<double>(begin: 0.8, end: 1.15)
        .animate(CurvedAnimation(parent: _orbCtrl, curve: Curves.easeInOut));
    _rot = Tween<double>(begin: 0, end: 2 * 3.14159).animate(_rotCtrl);
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    _rotCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03000D),
      body: Stack(
        children: [
          // Deep space radial bg
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.2,
                colors: [
                  Color(0xFF12003E),
                  Color(0xFF0A0020),
                  Color(0xFF03000D)
                ],
                stops: [0, 0.5, 1],
              ),
            ),
          ),

          // Orbiting dots
          AnimatedBuilder(
            animation: _rot,
            builder: (_, __) {
              return CustomPaint(
                size: Size(MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height),
                painter: _OrbitPainter(_rot.value),
              );
            },
          ),

          // Center content
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Breathing glowing orb with logo
                  AnimatedBuilder(
                    animation: _orb,
                    builder: (_, __) => Transform.scale(
                      scale: _orb.value,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(38),
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFFE8D5FF),
                              Color(0xFFBB86FC),
                              Color(0xFF5A1FC4)
                            ],
                            stops: [0, 0.45, 1],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFBB86FC).withOpacity(0.6),
                              blurRadius: 48,
                              spreadRadius: 8,
                            ),
                            BoxShadow(
                              color: const Color(0xFF7C4DFF).withOpacity(0.3),
                              blurRadius: 80,
                              spreadRadius: 20,
                            ),
                          ],
                        ),
                        child: ClipRRect(
  borderRadius: BorderRadius.circular(28),
  child: Image.asset(
    'assets/icon.png',
    fit: BoxFit.cover,
  ),
),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'LUCID',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mindful Screen Time',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8877AA),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Shimmer loading bar
                  _ShimmerBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final double angle;
  _OrbitPainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw 3 rings of orbiting particles
    final rings = [
      (
        r: size.width * 0.32,
        count: 8,
        color: const Color(0x33BB86FC),
        size: 3.0
      ),
      (
        r: size.width * 0.45,
        count: 12,
        color: const Color(0x2203DAC6),
        size: 2.0
      ),
      (
        r: size.width * 0.55,
        count: 6,
        color: const Color(0x447C4DFF),
        size: 4.0
      ),
    ];

    for (final ring in rings) {
      for (int i = 0; i < ring.count; i++) {
        final a = angle + (i * 2 * 3.14159 / ring.count);
        final x = cx + ring.r * cos(a);
        final y = cy + ring.r * sin(a);
        final twinkle = (sin(angle * 3 + i) * 0.3 + 0.7).abs();
        paint.color = ring.color.withOpacity(ring.color.opacity * twinkle);
        canvas.drawCircle(Offset(x, y), ring.size, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.angle != angle;
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

// ─── Onboarding Screen (first-launch only) ───────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({Key? key, required this.onDone}) : super(key: key);
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const _channel =
      MethodChannel('com.example.scroll_stop/accessibility');

  late final AnimationController _bgCtrl;
  late final Animation<double> _bgAnim;
  late final AnimationController _cardCtrl;
  late final Animation<Offset> _cardAnim;
  late final Animation<double> _fadeAnim;

  bool _accessibilityGranted = false;
  bool _usageGranted = false;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeOut);

    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _cardAnim = Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeIn);

    _checkPermissions();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    // Heuristic: try AppUsage to see if usage access is granted
    bool usageOk = false;
    try {
      final end = DateTime.now();
      await AppUsage()
          .getAppUsage(end.subtract(const Duration(seconds: 5)), end);
      usageOk = true;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _usageGranted = usageOk;
      });
    }
  }

  Future<void> _openAccessibility() async {
    try {
      await _channel.invokeMethod('openSettings');
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    await _checkPermissions();
  }

  Future<void> _openUsageAccess() async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bothGranted = _accessibilityGranted || _usageGranted;

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
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFBB86FC), Color(0xFF6200EE)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFBB86FC).withOpacity(0.5),
                              blurRadius: 28,
                              spreadRadius: 4,
                            )
                          ],
                        ),
                        child: const Center(
                          child: Text('✦',
                              style:
                                  TextStyle(fontSize: 30, color: Colors.white)),
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
                      const SizedBox(height: 12),
                      const Text(
                        'Two quick permissions and you\'re set.\nLucid needs these to guard your attention.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF9E9E9E),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

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
                        icon: '📊',
                        title: 'Usage Access',
                        description:
                            'Allows Lucid to read which app is in the foreground so it can track session time.',
                        granted: _usageGranted,
                        onGrant: _openUsageAccess,
                        grantLabel: 'Grant Usage Access',
                      ),
                      const SizedBox(height: 16),

                      // Info box for Redmi / MIUI users
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1225),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFBB86FC).withOpacity(0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('💡', style: TextStyle(fontSize: 18)),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'On Redmi / MIUI: If the Accessibility toggle appears greyed out, '
                                'go to Settings → Apps → Lucid → ⋮ menu → Allow restricted settings.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFBB86FC),
                                    height: 1.5),
                              ),
                            ),
                          ],
                        ),
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
                                'Get Started  →',
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
              child: Text(granted ? '✓' : icon,
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

// ─── Home Screen ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _apps = [];
  String _searchQuery = "";
  static const _channel =
      MethodChannel('com.example.scroll_stop/accessibility');

  bool _serviceEnabled = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;


  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadInstalledApps().then((_) {
      _loadSavedApps();
    });

    _checkServiceStatus();
  }

  @override
  void dispose() {
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
  }

  Future<void> _checkServiceStatus() async {
    try {
      final end = DateTime.now();
      await AppUsage()
          .getAppUsage(end.subtract(const Duration(seconds: 10)), end);
      if (mounted) setState(() => _serviceEnabled = true);
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
    Future.delayed(const Duration(seconds: 2), () => _checkServiceStatus());
  }

  Future<void> _toggleApp(int index, bool value) async {
    setState(() => _apps[index]['enabled'] = value);
    await _saveEnabledApps();
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _apps.where((a) => a['enabled'] == true).length;
    final filteredApps = _apps.where((app) {

  final name =
      app['name']
          .toString()
          .toLowerCase();

  return name.contains(
    _searchQuery.toLowerCase(),
  );

}).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App Bar ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFBB86FC), Color(0xFF6200EE)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFBB86FC).withOpacity(0.4),
                            blurRadius: 14,
                            spreadRadius: 1,
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text('✦',
                            style:
                                TextStyle(fontSize: 20, color: Colors.white)),
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

            // ── Status Card ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: _StatusCard(
                  pulseAnim: _pulseAnim,
                  serviceEnabled: _serviceEnabled,
                  onActivate: _openAccessibilitySettings,
                  enabledApps: enabledCount,
                ),
              ),
            ),

            // ── How It Works ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: _HowItWorksCard(),
              ),
            ),
SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(
      24,
      20,
      24,
      16,
    ),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF17152D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: const TextStyle(
          color: Colors.white,
        ),
        decoration: const InputDecoration(
          hintText: 'Search apps...',
          hintStyle: TextStyle(
            color: Colors.white54,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.white54,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    ),
  ),
),
            // ── App List Header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Monitored Apps',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C2E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$enabledCount active',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFBB86FC))),
                    ),
                  ],
                ),
              ),
            ),

            // ── App Tiles ─────────────────────────────────────────────────
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final app = filteredApps[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                    child: _AppTile(
                      icon: '📱',
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
                childCount: filteredApps.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Future<void> _loadInstalledApps() async {
    final apps = await InstalledApps.getInstalledApps();

    apps.sort(
      (a, b) => a.name.toLowerCase().compareTo(
            b.name.toLowerCase(),
          ),
    );

    setState(() {
      _apps.clear();

      for (var app in apps) {
        if (
          app.name.toLowerCase().contains("you") ||
          app.name.toLowerCase().contains("cam") ||
          app.name.toLowerCase().contains("calc") ||
          app.name.toLowerCase().contains("calendar")
        ) {
          print("${app.name} --> ${app.packageName}");
        }

        final package = app.packageName.toLowerCase();
        if (app.packageName == "com.example.lucid") {
          continue;
        }

        _apps.add({
          'name': app.name,
          'package': app.packageName,
          'enabled': false,
        });
      }
    });
  }
}

// ─── Status Card ──────────────────────────────────────────────────────────────

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

// ─── How It Works Card ────────────────────────────────────────────────────────

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
          _step('⏳', '60-Second Mindful Pause',
              'When you open a monitored app, a beautiful animated timer overlay appears. It vanishes once 60 seconds pass.'),
          const SizedBox(height: 12),
          _step('🔁', 'Session Tracking',
              'Once inside, you can freely switch tabs without interruption. The timer only re-appears if you leave and come back.'),
          const SizedBox(height: 12),
          _step('⏰', '15-Minutes Usage Reminder',
              'After your session limit, Lucid asks if you really want to keep scrolling — or do something better.'),
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

// ─── App Tile ─────────────────────────────────────────────────────────────────

class _AppTile extends StatelessWidget {
  final String icon;
  final String name;
  final String package;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AppTile({
    required this.icon,
    required this.name,
    required this.package,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        title: Text(name,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
        subtitle: Text(package,
            style: const TextStyle(color: Color(0xFF616161), fontSize: 11)),
        trailing: Switch(
          value: enabled,
          activeColor: const Color(0xFFBB86FC),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

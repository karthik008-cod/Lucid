import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:app_usage/app_usage.dart';
import 'package:url_launcher/url_launcher.dart';

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
      home: const HomeScreen(),
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
  static const _channel = MethodChannel('com.example.scroll_stop/accessibility');

  bool _serviceEnabled = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Background usage checking components
  Timer? _usageMonitorTimer;
  Timer? _overlayCountdownTimer;
  bool _isInterceptionActive = false;
  int _secondsRemaining = 60;
  String _activeTargetPackage = "";

  // Cooldown registry to prevent instant re-blocking after countdown finishes
  String _recentlyUnlockedApp = "";
  DateTime? _unlockTime;

  // List of monitored apps
  final List<Map<String, dynamic>> _apps = [
    {'name': 'Instagram',   'package': 'com.instagram.android',      'icon': '📸', 'enabled': true},
    {'name': 'YouTube',     'package': 'com.google.android.youtube', 'icon': '▶️', 'enabled': true},
    {'name': 'Snapchat',    'package': 'com.snapchat.android',       'icon': '👻', 'enabled': true},
    {'name': 'Twitter / X', 'package': 'com.twitter.android',        'icon': '🐦', 'enabled': false},
    {'name': 'Facebook',    'package': 'com.facebook.katana',         'icon': '👍', 'enabled': false},
    {'name': 'TikTok',      'package': 'com.zhiliaoapp.musically',    'icon': '🎵', 'enabled': false},
    {'name': 'Reddit',      'package': 'com.reddit.frontpage',        'icon': '🤖', 'enabled': false},
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Poll service checks and initiate the reactive background thread loop
    _checkServiceStatus();
    _startBackgroundUsageMonitor();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _usageMonitorTimer?.cancel();
    _overlayCountdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    try {
      DateTime endDate = DateTime.now();
      DateTime startDate = endDate.subtract(const Duration(seconds: 10));
      await AppUsage().getAppUsage(startDate, endDate);
      
      if (mounted) {
        setState(() {
          _serviceEnabled = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serviceEnabled = false;
        });
      }
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      // Direct intent path shortcut forcing the system setting profile window open
      await _channel.invokeMethod('openSettings');
    } on PlatformException catch (e) {
      debugPrint('Failed: ${e.message}');
    }
    
    // Re-verify the access flag status after the user comes back to the app window context
    Future.delayed(const Duration(seconds: 2), () => _checkServiceStatus());
  }

  void _startBackgroundUsageMonitor() {
    // Increased duration to 2 seconds to prevent hyper-aggressive OS limits
    _usageMonitorTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_serviceEnabled || _isInterceptionActive) return;

      try {
        DateTime endDate = DateTime.now();
        // Only look at the last 10 seconds to avoid falsely catching old usage
        DateTime startDate = endDate.subtract(const Duration(seconds: 10));
        List<AppUsageInfo> usageStats = await AppUsage().getAppUsage(startDate, endDate);

        for (var info in usageStats) {
          for (var app in _apps) {
            if (app['enabled'] == true && info.packageName == app['package']) {
              
              // COOLDOWN CHECK: Give the user 15 minutes of peace if they just waited out the timer
              if (_recentlyUnlockedApp == app['package'] && _unlockTime != null) {
                if (DateTime.now().difference(_unlockTime!).inMinutes < 15) {
                  continue; // Skip the block, they are in the cooldown period
                } else {
                  // Cooldown expired, reset the locks
                  _recentlyUnlockedApp = "";
                  _unlockTime = null;
                }
              }

              // Target identified in foreground. Fire the shield!
              _triggerMindfulInterception(app['package']);
              return; // Break the loop so it doesn't double-fire
            }
          }
        }
      } catch (_) {
        // CRITICAL FIX: If Xiaomi auto-pops the Settings screen or denies permission, 
        // switch off the engine immediately to DESTROY the infinite loop.
        if (mounted) {
          setState(() {
            _serviceEnabled = false;
          });
        }
      }
    });
  }

  void _triggerMindfulInterception(String packagePath) {
    setState(() {
      _isInterceptionActive = true;
      _secondsRemaining = 60;
      _activeTargetPackage = packagePath;
    });

    _overlayCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        _overlayCountdownTimer?.cancel();
        
        setState(() {
          _isInterceptionActive = false;
          // Register the cooldown lock so we don't instantly block it again!
          _recentlyUnlockedApp = _activeTargetPackage;
          _unlockTime = DateTime.now();
        });

        // Countdown safely concluded! Launch deep link target app externally
        String fallbackUrl = "https://www.google.com";
        if (_activeTargetPackage.contains("youtube")) fallbackUrl = "https://www.youtube.com";
        if (_activeTargetPackage.contains("instagram")) fallbackUrl = "https://www.instagram.com";
        if (_activeTargetPackage.contains("snapchat")) fallbackUrl = "https://www.snapchat.com";

        final Uri destinationUri = Uri.parse(fallbackUrl);
        if (await canLaunchUrl(destinationUri)) {
          await launchUrl(destinationUri, mode: LaunchMode.externalApplication);
        }
      }
    });
  }

  void _abortAndReturnHome() {
    _overlayCountdownTimer?.cancel();
    setState(() {
      _isInterceptionActive = false;
    });
    // Fire structural home-button fallback intent via system channels
    SystemNavigator.pop();
  }

  void _toggleApp(int index, bool value) {
    setState(() => _apps[index]['enabled'] = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _apps.where((a) => a['enabled'] == true).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Stack(
        children: [
          // Your untouched original design interface layer
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // ── App Bar ──────────────────────────────────────────────────
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
                          ),
                          child: const Center(
                            child: Text('✦', style: TextStyle(fontSize: 20, color: Colors.white)),
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
                                style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      final app = _apps[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                        child: _AppTile(
                          icon: app['icon'],
                          name: app['name'],
                          package: app['package'],
                          enabled: app['enabled'],
                          onChanged: (v) => _toggleApp(index, v),
                        ),
                      );
                    },
                    childCount: _apps.length,
                  ),
                ),

                // ── Bottom padding ────────────────────────────────────────────
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          ),

          // Core Mindfulness Shield Interception Overlay UI State
          if (_isInterceptionActive)
            Container(
              color: const Color(0xFF0D0D0D),
              width: double.infinity,
              height: double.infinity,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Pause & Reflect",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Lucid detected an implicit urge to check social feeds. Let's wait out the clock to regain complete focus control.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.5),
                      ),
                      const SizedBox(height: 54),
                      
                      // Immersive Circular Count Tracker View
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: CircularProgressIndicator(
                              value: _secondsRemaining / 60,
                              strokeWidth: 6,
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFBB86FC)),
                              backgroundColor: const Color(0xFF1C1C2E),
                            ),
                          ),
                          Text(
                            "${_secondsRemaining}s",
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w300, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 64),
                      
                      // Interception Exit/Escape Route Handle Action Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _abortAndReturnHome,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFE53935), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            "I'll Do Something Better",
                            style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
                    'A 60s loading screen & automated deep links are running.'
                  : 'Enable Usage Tracking parameters so Lucid can analyze foreground '
                    'app layers and block target packages.',
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
                    'Enable Tracker Access →',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Settings → Security & Privacy → Usage Access → Lucid',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E9E9E),
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3E2723),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD84315).withOpacity(0.5)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠️ ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Using a custom Redmi interface?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFCC80),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'If the tracking switch appears grayed out or displays restriction warnings:\n'
                            '1. Open native Settings → Apps → Manage Apps → Lucid.\n'
                            '2. Tap upper-right control menu configurations.\n'
                            '3. Toggle ON "Allow restricted settings" directly.\n'
                            '4. Complete the security permission setup steps.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFFFE0B2),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
          _step('1', '⏳', '60-Second Loading Screen',
              'When you open a monitored app, Lucid catches the focus shift and locks your screen with a 60-second friction wall.'),
          const SizedBox(height: 12),
          _step('2', '⚡', 'Instant Interception',
              'The core service uses reactive background metrics to instantly pull target layers down if app boundaries are crossed.'),
          const SizedBox(height: 12),
          _step('3', '🧠', 'Mindful Friction',
              'No permanent locks or native service dependencies—just clean layout interruptions to help break continuous scrolling loop trends.'),
        ],
      ),
    );
  }

  Widget _step(String num, String emoji, String title, String body) {
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
                      fontSize: 12,
                      color: Color(0xFF9E9E9E),
                      height: 1.4)),
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
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        title: Text(name,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
        subtitle: Text(package,
            style: const TextStyle(
                color: Color(0xFF616161), fontSize: 11)),
        trailing: Switch(
          value: enabled,
          activeColor: const Color(0xFFBB86FC),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

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

  // List of monitored apps
  final List<Map<String, dynamic>> _apps = [
    {'name': 'Instagram',   'package': 'com.instagram.android',      'icon': '📸', 'enabled': true},
    {'name': 'YouTube',     'package': 'com.google.android.youtube', 'icon': '▶️', 'enabled': true},
    {'name': 'Snapchat',    'package': 'com.snapchat.android',        'icon': '👻', 'enabled': true},
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
    _checkServiceStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkServiceStatus() async {
    // We'll just try calling a method; if it responds, service is active
    // For now keep as a visual-only toggle updated by user
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException catch (e) {
      debugPrint('Failed: ${e.message}');
    }
  }

  void _toggleApp(int index, bool value) {
    setState(() => _apps[index]['enabled'] = value);
    // TODO: sync to native Kotlin service via MethodChannel
  }

  @override
  Widget build(BuildContext context) {
    final enabledCount = _apps.where((a) => a['enabled'] == true).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
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
                  serviceEnabled ? 'Service Active' : 'Setup Required',
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
                    'A 60s loading screen & 15-min warnings are active.'
                  : 'Enable the Accessibility Service so Lucid can intercept '
                    'addictive apps and protect your focus.',
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
                    'Enable in Accessibility Settings →',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Settings → Accessibility → Downloaded apps → Lucid',
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
                            'Using Redmi Note 10t (MIUI)?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFFCC80),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'If it is grayed out or shows "Restricted setting":\n'
                            '1. Go to main phone Settings → Apps → Manage Apps → Lucid.\n'
                            '2. Tap the 3 dots in the top-right corner (or scroll to the bottom).\n'
                            '3. Turn ON "Allow restricted settings".\n'
                            '4. Go back to Accessibility and turn on Lucid.',
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
              'When you open a monitored app, Lucid shows a 60-second friction wall. You can escape or wait it out.'),
          const SizedBox(height: 12),
          _step('2', '⏰', 'Every 15 Minutes',
              'After you get in, a popup appears every 15 minutes reminding you of the time spent.'),
          const SizedBox(height: 12),
          _step('3', '🧠', 'Your Choice',
              'You can dismiss the warning and keep going, or tap to go home. No hard blocks — just mindful friction.'),
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
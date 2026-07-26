import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class TourPageData {
  final String title;
  final String body;
  final Color primaryColor;
  final String primaryButtonText;
  final String? secondaryButtonText;
  final Widget Function(bool isActive, bool isDark) illustrationBuilder;

  TourPageData({
    required this.title,
    required this.body,
    required this.primaryColor,
    required this.primaryButtonText,
    this.secondaryButtonText,
    required this.illustrationBuilder,
  });
}

class InteractiveTourScreen extends StatefulWidget {
  final VoidCallback onDone;
  final bool isHelpMode;

  const InteractiveTourScreen({
    super.key,
    required this.onDone,
    this.isHelpMode = false,
  });

  @override
  State<InteractiveTourScreen> createState() => _InteractiveTourScreenState();
}

class _InteractiveTourScreenState extends State<InteractiveTourScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  int _currentPage = 0;

  final List<TourPageData> _pages = [
    TourPageData(
      title: 'Lost track of time again?',
      body: 'Hey there 👋\n\nHave you ever opened an app just for a quick peek... and somehow an entire hour slipped away?\n\nYou\'re definitely not alone. If you\'re ready to build healthier habits, I\'m here to guide you.',
      primaryColor: const Color(0xFFF43F5E), // Rose
      primaryButtonText: 'Yes, help me',
      secondaryButtonText: 'Skip',
      illustrationBuilder: (active, dark) => DoomScrollingIllustration(isActive: active, isDark: dark),
    ),
    TourPageData(
      title: 'Meet your 60-second pause',
      body: 'I won\'t block you from your favorite apps forever.\n\nWhenever you open a chosen app, I\'ll simply ask you to breathe for 60 seconds.\n\nThat brief pause is all your brain needs to decide if you really want to scroll.',
      primaryColor: const Color(0xFF34D399), // Emerald
      primaryButtonText: 'Makes sense',
      illustrationBuilder: (active, dark) => MindfulPauseIllustration(isActive: active, isDark: dark),
    ),
    TourPageData(
      title: 'It\'s okay to continue',
      body: 'If you wait through the 60 seconds and still want to jump in... go ahead.\n\nThe decision always remains yours. Habits take time to change, and I\'m not here to judge you.',
      primaryColor: const Color(0xFFFBBF24), // Amber
      primaryButtonText: 'I like that',
      illustrationBuilder: (active, dark) => ReminderIllustration(isActive: active, isDark: dark),
    ),
    TourPageData(
      title: 'Set your own pace',
      body: 'Every app is different, and so are your goals.\n\nWant 15 minutes for Instagram but 30 for YouTube? You decide.\n\nYou can set a custom reminder timer for each app individually, completely tailored to your life.',
      primaryColor: const Color(0xFF38BDF8), // Sky Blue
      primaryButtonText: 'Perfect',
      illustrationBuilder: (active, dark) => CustomTimersIllustration(isActive: active, isDark: dark),
    ),
    TourPageData(
      title: 'Your journey begins 🌱',
      body: 'That\'s everything!\n\nRemember, I\'m not here to stop you from using your phone. I\'m only here to help you use it with intention.\n\nWhenever you\'re ready, let\'s set everything up together.',
      primaryColor: const Color(0xFFC084FC), // Purple
      primaryButtonText: 'Let\'s Get Started',
      illustrationBuilder: (active, dark) => SunriseIllustration(isActive: active, isDark: dark),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      HapticFeedback.lightImpact();
      _pageController.nextPage(
        duration: const Duration(milliseconds: 800),
        curve: Curves.fastEaseInToSlowEaseOut,
      );
    } else {
      HapticFeedback.mediumImpact();
      widget.onDone();
    }
  }

  void _skip() {
    HapticFeedback.lightImpact();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.isHelpMode)
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      onPressed: _skip,
                      tooltip: 'Close Tour',
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                  HapticFeedback.selectionClick();
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _TourPageWidget(
                    data: _pages[index],
                    isActive: index == _currentPage,
                    isDark: isDark,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        height: 6.0,
                        width: _currentPage == index ? 28.0 : 6.0,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  _AnimatedButton(
                    text: _pages[_currentPage].primaryButtonText,
                    onTap: _nextPage,
                    isPrimary: true,
                    color: theme.colorScheme.primary,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: _pages[_currentPage].secondaryButtonText != null ? 60.0 : 0.0,
                    curve: Curves.easeOutCubic,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          if (_pages[_currentPage].secondaryButtonText != null)
                            _AnimatedButton(
                              text: _pages[_currentPage].secondaryButtonText!,
                              onTap: _skip,
                              isPrimary: false,
                              color: theme.colorScheme.onSurface,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourPageWidget extends StatelessWidget {
  final TourPageData data;
  final bool isActive;
  final bool isDark;

  const _TourPageWidget({
    required this.data,
    required this.isActive,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 160,
            width: double.infinity,
            child: data.illustrationBuilder(isActive, isDark),
          ),
          const SizedBox(height: 48),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: isActive ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSerifDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: isActive ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Text(
                    data.body,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AnimatedButton extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final bool isPrimary;
  final Color color;

  const _AnimatedButton({
    required this.text,
    required this.onTap,
    required this.isPrimary,
    required this.color,
  });

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) => _controller.forward();
  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14.0),
          decoration: BoxDecoration(
            color: widget.isPrimary ? widget.color : widget.color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(28.0),
            border: widget.isPrimary ? null : Border.all(color: widget.color.withValues(alpha: 0.2), width: 1.5),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    )
                  ]
                : null,
          ),
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: widget.isPrimary ? Colors.white : widget.color,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ILLUSTRATION 1: DOOM SCROLLING
// ==========================================
class DoomScrollingIllustration extends StatefulWidget {
  final bool isActive;
  final bool isDark;
  const DoomScrollingIllustration({super.key, required this.isActive, required this.isDark});
  @override
  State<DoomScrollingIllustration> createState() => _DoomScrollingIllustrationState();
}
class _DoomScrollingIllustrationState extends State<DoomScrollingIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFFF43F5E);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        final floatY = math.sin(t * 2 * math.pi) * 8;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: widget.isActive ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.elasticOut,
          builder: (context, activeVal, child) {
            return Transform.scale(
              scale: 0.8 + (0.2 * activeVal),
              child: Opacity(
                opacity: activeVal.clamp(0.0, 1.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background glow
                    Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.1),
                        boxShadow: [
                          BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 40, spreadRadius: 10)
                        ]
                      ),
                    ),
                    // Floating icons
                    _buildFloatingIcon(Icons.camera_alt_rounded, color, -60, -40 + floatY, 0.8, t),
                    _buildFloatingIcon(Icons.play_arrow_rounded, color, 60, -20 - floatY, 0.6, t + 0.5),
                    _buildFloatingIcon(Icons.forum_rounded, color, -40, 50 + floatY, 0.7, t + 0.25),
                    // Phone
                    Transform.translate(
                      offset: Offset(0, floatY * 0.5),
                      child: Container(
                        width: 60, height: 110,
                        decoration: BoxDecoration(
                          color: widget.isDark ? Colors.grey[850] : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: color.withValues(alpha: 0.3), width: 3),
                          boxShadow: [
                            BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 5))
                          ]
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildLine(color, 30),
                            _buildLine(color, 40),
                            _buildLine(color, 25),
                          ],
                        ),
                      ),
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
  Widget _buildFloatingIcon(IconData icon, Color color, double dx, double dy, double scale, double t) {
    final floatX = math.cos(t * 2 * math.pi) * 5;
    return Transform.translate(
      offset: Offset(dx + floatX, dy),
      child: Transform.scale(
        scale: scale,
        child: Icon(icon, color: color.withValues(alpha: 0.6), size: 32),
      ),
    );
  }
  Widget _buildLine(Color color, double width) {
    return Container(
      height: 4, width: width,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2)
      ),
    );
  }
}

// ==========================================
// ILLUSTRATION 2: MINDFUL PAUSE
// ==========================================
class MindfulPauseIllustration extends StatefulWidget {
  final bool isActive;
  final bool isDark;
  const MindfulPauseIllustration({super.key, required this.isActive, required this.isDark});
  @override
  State<MindfulPauseIllustration> createState() => _MindfulPauseIllustrationState();
}
class _MindfulPauseIllustrationState extends State<MindfulPauseIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF34D399);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: widget.isActive ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.fastOutSlowIn,
          builder: (context, activeVal, child) {
            return Transform.scale(
              scale: 0.9 + (0.1 * activeVal),
              child: Opacity(
                opacity: activeVal.clamp(0.0, 1.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Phone Base
                    Container(
                      width: 80, height: 160,
                      decoration: BoxDecoration(
                        color: widget.isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 20)]
                      ),
                    ),
                    // Progress Ring
                    SizedBox(
                      width: 120, height: 120,
                      child: CircularProgressIndicator(
                        value: activeVal < 0.5 ? 0 : (activeVal - 0.5) * 2,
                        strokeWidth: 6,
                        backgroundColor: color.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation(color),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    // Shield Icon
                    Transform.scale(
                      scale: 1.0 + (math.sin(t * 2 * math.pi) * 0.05),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.shield_rounded, color: color, size: 36),
                      ),
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
}

// ==========================================
// ILLUSTRATION 3: REMINDER
// ==========================================
class ReminderIllustration extends StatefulWidget {
  final bool isActive;
  final bool isDark;
  const ReminderIllustration({super.key, required this.isActive, required this.isDark});
  @override
  State<ReminderIllustration> createState() => _ReminderIllustrationState();
}
class _ReminderIllustrationState extends State<ReminderIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFFFBBF24);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final floatY = math.sin(_ctrl.value * 2 * math.pi) * 6;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: widget.isActive ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutBack,
          builder: (context, activeVal, child) {
            return Opacity(
              opacity: activeVal.clamp(0.0, 1.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Phone
                  Container(
                    width: 70, height: 140,
                    decoration: BoxDecoration(
                      color: widget.isDark ? Colors.grey[850] : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
                    ),
                  ),
                  // Notification Drop
                  Transform.translate(
                    offset: Offset(0, -60 + (60 * activeVal) + floatY),
                    child: Container(
                      width: 110, height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 5))]
                      ),
                      child: const Center(
                        child: Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  // Floating Hearts
                  _buildHeart(color, -50, -20, _ctrl.value),
                  _buildHeart(color, 50, 30, _ctrl.value + 0.5),
                ],
              ),
            );
          },
        );
      },
    );
  }
  Widget _buildHeart(Color color, double dx, double dy, double t) {
    return Transform.translate(
      offset: Offset(dx, dy - (t * 20)),
      child: Opacity(
        opacity: (1.0 - t).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.5 + (t * 0.5),
          child: Icon(Icons.favorite_rounded, color: color.withValues(alpha: 0.5), size: 24),
        ),
      ),
    );
  }
}

// ==========================================
// ILLUSTRATION 4: CUSTOM TIMERS
// ==========================================
class CustomTimersIllustration extends StatefulWidget {
  final bool isActive;
  final bool isDark;
  const CustomTimersIllustration({super.key, required this.isActive, required this.isDark});
  @override
  State<CustomTimersIllustration> createState() => _CustomTimersIllustrationState();
}
class _CustomTimersIllustrationState extends State<CustomTimersIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF38BDF8);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: widget.isActive ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, activeVal, child) {
        return Opacity(
          opacity: activeVal.clamp(0.0, 1.0),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final floatX = math.sin(_ctrl.value * math.pi) * 4;
              return Stack(
                alignment: Alignment.center,
                children: [
                  _buildCard(color, "15m", -40, -50, activeVal, floatX, Icons.camera_alt_rounded),
                  _buildCard(color, "30m", 0, 0, activeVal - 0.2, -floatX, Icons.play_arrow_rounded),
                  _buildCard(color, "10m", 40, 50, activeVal - 0.4, floatX, Icons.forum_rounded),
                ],
              );
            },
          ),
        );
      },
    );
  }
  Widget _buildCard(Color color, String text, double dx, double dy, double activeVal, double floatX, IconData icon) {
    if (activeVal < 0) activeVal = 0;
    return Transform.translate(
      offset: Offset(dx + floatX + (50 * (1 - activeVal)), dy),
      child: Opacity(
        opacity: activeVal.clamp(0.0, 1.0),
        child: Container(
          width: 130, height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ILLUSTRATION 5: SUNRISE
// ==========================================
class SunriseIllustration extends StatefulWidget {
  final bool isActive;
  final bool isDark;
  const SunriseIllustration({super.key, required this.isActive, required this.isDark});
  @override
  State<SunriseIllustration> createState() => _SunriseIllustrationState();
}
class _SunriseIllustrationState extends State<SunriseIllustration> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFFC084FC);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: widget.isActive ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeOutCubic,
          builder: (context, activeVal, child) {
            return Opacity(
              opacity: activeVal.clamp(0.0, 1.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Sun
                  Transform.translate(
                    offset: Offset(0, 60 - (60 * activeVal)),
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.2),
                        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 50)]
                      ),
                      child: Center(
                        child: Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                        ),
                      ),
                    ),
                  ),
                  // Horizon Line
                  Positioned(
                    bottom: 40,
                    child: Container(
                      width: 200, height: 4,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2)
                      ),
                    ),
                  ),
                  // Leaves
                  _buildLeaf(color, -60, -20, t),
                  _buildLeaf(color, 60, 20, t + 0.3),
                  _buildLeaf(color, -30, 40, t + 0.6),
                ],
              ),
            );
          },
        );
      },
    );
  }
  Widget _buildLeaf(Color color, double dx, double dy, double t) {
    if (t > 1.0) t -= 1.0;
    return Transform.translate(
      offset: Offset(dx + (math.sin(t * math.pi * 2) * 20), dy - (t * 60)),
      child: Transform.rotate(
        angle: t * math.pi * 2,
        child: Opacity(
          opacity: (math.sin(t * math.pi)).clamp(0.0, 1.0),
          child: Icon(Icons.eco_rounded, color: color.withValues(alpha: 0.6), size: 24),
        ),
      ),
    );
  }
}

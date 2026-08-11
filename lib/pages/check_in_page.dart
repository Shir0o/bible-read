import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/vibration_service.dart';

enum CheckInTimeOfDay { dawn, day, dusk, night }

CheckInTimeOfDay getTimeOfDay([DateTime? d]) {
  final now = d ?? DateTime.now();
  final h = now.hour;
  if (h < 11) return CheckInTimeOfDay.dawn;
  if (h < 17) return CheckInTimeOfDay.day;
  if (h < 21) return CheckInTimeOfDay.dusk;
  return CheckInTimeOfDay.night;
}

/// Standalone full-screen Check-In page ("Did you read today?").
///
/// Features:
///  • Dynamic sky background based on time of day (dawn, day, dusk, night) with motion.
///  • Large interactive sun button that rises on tap.
///  • Sunrise-gold flood animation upon confirmation.
///  • "Thank you for being here" payoff view displaying season count & reflection option.
class CheckInPage extends StatefulWidget {
  final bool readToday;
  final int seasonDays;
  final String? reflection;
  final Future<void> Function()? onConfirmRead;
  final VoidCallback? onReflect;
  final VoidCallback onClose;
  final DateTime Function()? dateProvider;
  final VibrationService vibrationService;
  final bool enableDriftAnimation;

  const CheckInPage({
    super.key,
    required this.readToday,
    this.seasonDays = 0,
    this.reflection,
    this.onConfirmRead,
    this.onReflect,
    required this.onClose,
    this.dateProvider,
    this.vibrationService = const VibrationService(),
    this.enableDriftAnimation = true,
  });

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage>
    with TickerProviderStateMixin {
  late bool _done;
  CheckInTimeOfDay _tod = CheckInTimeOfDay.day;
  late AnimationController _driftController;
  late AnimationController _floodController;
  late AnimationController _sunRiseController;
  late Animation<double> _floodScale;
  late Animation<double> _payoffOpacity;
  late Animation<Offset> _payoffSlide;

  /// Re-checks the time of day so an open screen shifts its sky at the hour
  /// boundary instead of freezing the gradient from when it opened.
  Timer? _timeOfDayTimer;

  bool _isSaving = false;

  bool get _inTestEnvironment => WidgetsBinding.instance.runtimeType
      .toString()
      .toLowerCase()
      .contains('test');

  @override
  void initState() {
    super.initState();
    _done = widget.readToday;
    _tod = getTimeOfDay(widget.dateProvider?.call() ?? DateTime.now());

    // Ambient sky drift motion.
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // Sun rise motion — springy, matching the design's `bottom .8s
    // cubic-bezier(.2,1.15,.3,1)` (a modest overshoot, not a rubber-band fling).
    _sunRiseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: _done ? 1.0 : 0.0,
    );

    // Flood & payoff animation.
    _floodController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: _done ? 1.0 : 0.0,
    );

    _floodScale = Tween<double>(begin: 0.0, end: 11.0).animate(
      CurvedAnimation(
        parent: _floodController,
        curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _payoffOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _floodController,
        curve: const Interval(0.28, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _payoffSlide =
        Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _floodController,
        curve: const Interval(0.28, 1.0, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTestEnv = _inTestEnvironment;

    if (!isTestEnv &&
        widget.enableDriftAnimation &&
        TickerMode.valuesOf(context).enabled) {
      if (!_driftController.isAnimating) {
        _driftController.repeat(reverse: true);
      }
    } else {
      _driftController.stop();
    }

    // Keep the time-of-day gradient live while the screen is open.
    if (!isTestEnv) {
      _timeOfDayTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
        final next =
            getTimeOfDay(widget.dateProvider?.call() ?? DateTime.now());
        if (next != _tod && mounted) {
          setState(() => _tod = next);
        }
      });
    }
  }

  @override
  void dispose() {
    _timeOfDayTimer?.cancel();
    _driftController.dispose();
    _sunRiseController.dispose();
    _floodController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    if (_done || _isSaving) return;

    widget.vibrationService.heavyImpact();

    setState(() {
      _done = true;
      _isSaving = true;
    });

    _sunRiseController.forward();
    _floodController.forward();

    try {
      if (widget.onConfirmRead != null) {
        await widget.onConfirmRead!();
      }
    } catch (_) {
      // Revert if saving fails
      if (mounted) {
        setState(() {
          _done = false;
          _isSaving = false;
        });
        _sunRiseController.reverse();
        _floodController.reverse();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  List<Color> _getSkyGradientColors() {
    switch (_tod) {
      case CheckInTimeOfDay.dawn:
        return const [
          Color(0xFFFFD3A6),
          Color(0xFFFFB4B8),
          Color(0xFFD9BDE8),
          Color(0xFFC3BCEE),
        ];
      case CheckInTimeOfDay.day:
        return const [
          Color(0xFFBFE6F7),
          Color(0xFFD8ECF6),
          Color(0xFFEFE6D8),
          Color(0xFFF6E9D4),
        ];
      case CheckInTimeOfDay.dusk:
        return const [
          Color(0xFFF9B98A),
          Color(0xFFE997AE),
          Color(0xFF9A7FCB),
          Color(0xFF6C5EA8),
        ];
      case CheckInTimeOfDay.night:
        return const [
          Color(0xFF241F3C),
          Color(0xFF332A55),
          Color(0xFF463A72),
          Color(0xFF5A4B8C),
        ];
    }
  }

  Color get _textColor {
    return _tod == CheckInTimeOfDay.night
        ? const Color(0xFFFFF3DE)
        : const Color(0xFF2A2438);
  }

  Color get _sunBorderColor {
    return _tod == CheckInTimeOfDay.night
        ? const Color(0xFF1A1630)
        : const Color(0xFF2A2438);
  }

  @override
  Widget build(BuildContext context) {
    // Re-evaluate the time of day on every build so the sky always matches the
    // current hour (see also [_timeOfDayTimer] for boundary crossings while the
    // screen stays open).
    _tod = getTimeOfDay(widget.dateProvider?.call() ?? DateTime.now());
    final skyColors = _getSkyGradientColors();

    return Scaffold(
      body: Stack(
        children: [
          // 1. Sky background with gradient & drift motion
          AnimatedBuilder(
            animation: _driftController,
            builder: (context, child) {
              final alignY = -0.5 + (_driftController.value * 0.3);
              return Container(
                key: const ValueKey('checkin_sky'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(0, alignY),
                    end: Alignment(0, 1.0 + (alignY * 0.2)),
                    colors: skyColors,
                    stops: const [0.0, 0.38, 0.70, 1.0],
                  ),
                ),
              );
            },
          ),

          // 2. Radial gold flood animation when confirmed
          AnimatedBuilder(
            animation: _floodController,
            builder: (context, child) {
              if (_floodScale.value <= 0.001) return const SizedBox.shrink();
              return Center(
                child: Transform.scale(
                  scale: _floodScale.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Color(0xFFFFF2C4),
                          Color(0xFFFFD470),
                          Color(0xFFF6A93C),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 4. "Did you read today?" Title
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            top: _done ? 60 : 120,
            left: 32,
            right: 32,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _done ? 0.0 : 1.0,
              child: Text(
                'Did you read today?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Hanken Grotesk',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _textColor,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
          ),

          // 5. Sun Button on Horizon
          AnimatedBuilder(
            animation: _sunRiseController,
            builder: (context, child) {
              final progress = CurvedAnimation(
                parent: _sunRiseController,
                curve: Curves.easeOutBack,
              ).value;
              // Design: the sun rests on the horizon (bottom 190) and rises to
              // bottom 500. Clamp the risen height so the sun never leaves the
              // top of the screen on short viewports.
              final screenHeight = MediaQuery.sizeOf(context).height;
              const sunSize = 168.0;
              final risenBottom = math.min(
                500.0,
                screenHeight - sunSize - 60,
              );
              final bottomOffset = 190.0 + (progress * (risenBottom - 190.0));

              return Positioned(
                bottom: bottomOffset,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _done ? null : _handleConfirm,
                    child: Container(
                      key: const ValueKey('checkin_sun'),
                      width: 168,
                      height: 168,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _sunBorderColor, width: 3.5),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFE9A8), Color(0xFFFFC24D)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _sunBorderColor,
                            offset: const Offset(0, 8),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 42,
                            color: const Color(0xFF2A2438),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'I READ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Color(0xFF2A2438),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 6. Payoff Content ("Thank you for being here" & Streak Count & Actions)
          if (_done)
            AnimatedBuilder(
              animation: _floodController,
              builder: (context, child) {
                return SlideTransition(
                  position: _payoffSlide,
                  child: FadeTransition(
                    opacity: _payoffOpacity,
                    child: SafeArea(
                      child: Stack(
                        children: [
                          // The affirmation/count block is centered in the sky,
                          // below the risen sun (design `.ci-payoff`).
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 26),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${widget.seasonDays}',
                                      style: const TextStyle(
                                        fontSize: 68,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF2A2438),
                                        height: 1.0,
                                        letterSpacing: -1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'days this season',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2A2438),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Thank you for being here',
                                      style: TextStyle(
                                        fontFamily: 'Spectral',
                                        fontSize: 21,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(
                                          0xFF2A2438,
                                        ).withValues(alpha: 0.75),
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // The two ways out stay pinned to the bottom
                          // (design `.ci-outs`), clear of the payoff text.
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                0,
                                32,
                                24,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.onReflect != null)
                                    SizedBox(
                                      width: double.infinity,
                                      height: 54,
                                      child: OutlinedButton(
                                        onPressed: widget.onReflect,
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFFFFDF8,
                                          ).withValues(alpha: 0.75),
                                          foregroundColor:
                                              const Color(0xFF2A2438),
                                          side: const BorderSide(
                                            color: Color(0xFF2A2438),
                                            width: 3,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: Text(
                                          widget.reflection != null &&
                                                  widget.reflection!.isNotEmpty
                                              ? 'Edit your reflection'
                                              : 'Add a reflection',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (widget.onReflect != null)
                                    const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: ElevatedButton(
                                      onPressed: widget.onClose,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF2A2438),
                                        foregroundColor:
                                            const Color(0xFFFFF3DE),
                                        side: const BorderSide(
                                          color: Color(0xFF2A2438),
                                          width: 3,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: const Text(
                                        'Done',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Top dismiss button (chevron down)
          if (!_done)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Semantics(
                    button: true,
                    label: 'Dismiss check-in',
                    child: IconButton(
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 38,
                        color: _textColor.withValues(alpha: 0.6),
                      ),
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

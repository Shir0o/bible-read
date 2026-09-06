import 'dart:async';

import 'package:flutter/material.dart';

import '../models/read_through.dart';
import '../services/vibration_service.dart';
import '../theme/app_theme.dart';

/// The full-screen moment shown when a user finishes a testament.
///
/// One celebration per marking, however many read-throughs that marking
/// completed: finishing the New Testament can also close a whole-Bible pair,
/// and two full-screen animations back to back would be a dismiss-chore at the
/// exact moment the app wants to feel generous.
///
/// The whole-Bible half carries its own explanation, because the count moving
/// at the moment the user finished a *testament* reads as a bug otherwise.
class ReadThroughCelebration extends StatefulWidget {
  /// Every record this marking produced, testament first.
  final List<ReadThrough> completed;

  /// How many times the user has now finished each scope.
  final ReadThroughCounts counts;

  final VoidCallback onDismiss;
  final VoidCallback? onAddLocation;
  final VibrationService vibrationService;

  const ReadThroughCelebration({
    super.key,
    required this.completed,
    required this.counts,
    required this.onDismiss,
    this.onAddLocation,
    this.vibrationService = const VibrationService(),
  });

  /// The testament record that triggered this celebration.
  ReadThrough get testament => completed.firstWhere(
        (r) => r.scope != ReadThroughScope.wholeBible,
        orElse: () => completed.first,
      );

  /// The whole-Bible record this marking closed, when it closed one.
  ReadThrough? get wholeBible {
    for (final row in completed) {
      if (row.scope == ReadThroughScope.wholeBible) return row;
    }
    return null;
  }

  @override
  State<ReadThroughCelebration> createState() => _ReadThroughCelebrationState();
}

class _ReadThroughCelebrationState extends State<ReadThroughCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
    unawaited(widget.vibrationService.mediumImpact());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A staggered fade-and-rise, [order] steps into the sequence.
  Widget _step(int order, Widget child) {
    final start = (order * 0.14).clamp(0.0, 0.8);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, (start + 0.45).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - curve.value)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final testament = widget.testament;
    final bible = widget.wholeBible;

    // The celebration keeps the app's night palette in both themes: the moment
    // should feel set apart from the everyday warm-paper screens.
    const ground = Color(0xFF16121D);
    const ink = Color(0xFFECE7F3);
    const dim = Color(0xFFA39CB3);
    const gold = Color(0xFFE1B488);

    return Material(
      color: ground,
      child: Semantics(
        label: 'You finished the ${testament.scope.label} for the '
            '${testament.ordinalLabel}',
        child: Stack(
          children: [
            Positioned(
              top: -150,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 620,
                  height: 620,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x33FFC24D),
                        Color(0x1AC6B4EC),
                        Color(0x0016121D),
                      ],
                      stops: [0.0, 0.42, 0.7],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _step(0, const _CelebrationMark()),
                          const SizedBox(height: 22),
                          _step(
                            1,
                            Column(
                              children: [
                                Text(
                                  '${testament.scope.label.toUpperCase()} · '
                                  'LAP ${testament.lapNumber}',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontUi,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.6,
                                    color: gold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _headline(testament),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontSerif,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: -0.5,
                                    height: 1.15,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (bible != null) ...[
                            const SizedBox(height: 22),
                            _step(2, _WholeBibleBand(counts: widget.counts)),
                          ] else ...[
                            const SizedBox(height: 12),
                            _step(
                              2,
                              Text(
                                _soloFooter(widget.counts, testament),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontUi,
                                  fontSize: 15,
                                  height: 1.5,
                                  color: dim,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _step(
                      4,
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: AppSpacing.buttonHeight,
                            child: FilledButton(
                              onPressed: widget.onDismiss,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFC6B4EC),
                                foregroundColor: const Color(0xFF22153D),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.rButton,
                                  ),
                                ),
                              ),
                              child: const Text('Keep it'),
                            ),
                          ),
                          if (widget.onAddLocation != null) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: AppSpacing.buttonHeight,
                              child: OutlinedButton(
                                onPressed: widget.onAddLocation,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: ink,
                                  side: const BorderSide(
                                    color: Color(0x33FFFFFF),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.rButton,
                                    ),
                                  ),
                                ),
                                child: const Text('Add where you were'),
                              ),
                            ),
                          ],
                        ],
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
  }

  static String _headline(ReadThrough testament) {
    final what = testament.scope == ReadThroughScope.oldTestament
        ? 'The Old Testament'
        : 'The New Testament';
    return switch (testament.lapNumber) {
      1 => '$what,\nall the way through.',
      2 => '$what,\na second time.',
      3 => '$what,\na third time.',
      _ => '$what,\nfor the ${_ordinalWord(testament.lapNumber)} time.',
    };
  }

  static String _soloFooter(ReadThroughCounts counts, ReadThrough testament) {
    final other = testament.scope == ReadThroughScope.oldTestament
        ? ReadThroughScope.newTestament
        : ReadThroughScope.oldTestament;
    final behind = counts.forScope(testament.scope) - counts.forScope(other);
    if (behind <= 0) return 'That is one more time through.';
    final label = other == ReadThroughScope.oldTestament
        ? 'Old Testament'
        : 'New Testament';
    return behind == 1
        ? 'One more $label and it makes a whole Bible.'
        : '$behind more times through the $label and they make whole Bibles.';
  }

  static String _ordinalWord(int n) => switch (n) {
        4 => 'fourth',
        5 => 'fifth',
        6 => 'sixth',
        7 => 'seventh',
        8 => 'eighth',
        9 => 'ninth',
        10 => 'tenth',
        _ => '${n}th',
      };
}

/// The gold sun disc with a check — the app's own mark, at celebration scale.
class _CelebrationMark extends StatelessWidget {
  const _CelebrationMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2A2438), width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE9A8), Color(0xFFFFC24D)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x4DFFC24D), blurRadius: 40),
        ],
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 52,
        color: Color(0xFF2A2438),
      ),
    );
  }
}

/// Explains why the whole-Bible count moved when a *testament* was finished.
class _WholeBibleBand extends StatelessWidget {
  final ReadThroughCounts counts;

  const _WholeBibleBand({required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0x29E1B488),
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: const Color(0x57E1B488)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AND YOUR ${_ordinal(counts.wholeBible).toUpperCase()} WHOLE BIBLE',
            style: const TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: Color(0xFFE1B488),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The two testaments have paired off.',
            style: TextStyle(
              fontFamily: AppTheme.fontSerif,
              fontSize: 19,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              height: 1.35,
              color: Color(0xFFF5E0CC),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _tally(counts),
            style: const TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 14,
              height: 1.45,
              color: Color(0xFFA39CB3),
            ),
          ),
        ],
      ),
    );
  }

  static String _tally(ReadThroughCounts counts) {
    final ot = counts.oldTestament;
    final nt = counts.newTestament;
    final bible = counts.wholeBible;
    final testaments = '$nt New Testament${nt == 1 ? "" : "s"}, $ot Old';
    final times = bible == 1 ? 'one complete time' : '$bible complete times';
    return '$testaments — that makes $times through.';
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}

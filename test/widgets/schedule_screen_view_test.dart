import 'package:bible_read/services/catch_up_engine.dart';
import 'package:bible_read/widgets/schedule_screen_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds schedule entries with readable 'Genesis N' readings; entries whose
/// index is in [completed] count as marked.
List<ScheduleEntry> _entries(
  List<({int dayOffset, bool completed})> days,
  DateTime today, {
  Set<int> completed = const {},
}) =>
    [
      for (var i = 0; i < days.length; i++)
        ScheduleEntry(
          index: i,
          date: today.add(Duration(days: days[i].dayOffset)),
          readings: ['Genesis ${i + 1}'],
          completed: completed.contains(i),
        ),
    ];

/// Builds a [CatchUpStatus] from explicit day offsets relative to [today],
/// so each test controls exactly which rows are done/current/missed/upcoming.
CatchUpStatus _status({
  required List<({int dayOffset, bool completed})> days,
  required DateTime today,
}) {
  final completed = {
    for (var i = 0; i < days.length; i++)
      if (days[i].completed) i,
  };
  return CatchUpEngine.compute(
    _entries(days, today, completed: completed),
    today: today,
  );
}

Widget _host(CatchUpStatus status, {bool isGroup = true}) {
  return MaterialApp(
    home: Scaffold(
      body: ScheduleScreenView(
        status: status,
        title: 'Test Plan',
        isGroup: isGroup,
        onToggle: (_) {},
        todayAnchorBuilder: isGroup ? (_) => const Text('GROUP ANCHOR') : null,
      ),
    ),
  );
}

/// Host that applies an optimistic completion when a row is toggled, mirroring
/// how the plan detail and full schedule pages feed the view.
class _OptimisticHost extends StatefulWidget {
  const _OptimisticHost({
    required this.days,
    required this.today,
    this.isGroup = true,
  });

  final List<({int dayOffset, bool completed})> days;
  final DateTime today;
  final bool isGroup;

  @override
  State<_OptimisticHost> createState() => _OptimisticHostState();
}

class _OptimisticHostState extends State<_OptimisticHost> {
  late final Set<int> _completed = {
    for (var i = 0; i < widget.days.length; i++)
      if (widget.days[i].completed) i,
  };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ScheduleScreenView(
          status: CatchUpEngine.compute(
            _entries(widget.days, widget.today, completed: _completed),
            today: widget.today,
          ),
          title: 'Test Plan',
          isGroup: widget.isGroup,
          onToggle: (i) => setState(() => _completed.add(i)),
          todayAnchorBuilder:
              widget.isGroup ? (_) => const Text('GROUP ANCHOR') : null,
        ),
      ),
    );
  }
}

/// Element of the tappable row wrapping [text].
Element _rowElement(WidgetTester tester, Finder text) => tester.element(
      find.ancestor(of: text, matching: find.byType(InkWell)).first,
    );

/// Background color of the schedule row containing [text].
Color? _rowBackground(WidgetTester tester, Finder text) {
  final row = find.ancestor(
    of: text,
    matching: find.byWidgetPredicate(
      (w) =>
          (w is Container && w.decoration is BoxDecoration) ||
          (w is AnimatedContainer && w.decoration is BoxDecoration),
    ),
  );
  expect(row, findsAtLeastNWidgets(1));
  // The innermost match is the container the row actually renders with
  // (AnimatedContainer builds a plain Container inside itself).
  final widget = tester.widget(row.last);
  final Decoration? decoration = widget is Container
      ? widget.decoration
      : (widget as AnimatedContainer).decoration;
  return (decoration as BoxDecoration).color;
}

void main() {
  final today = DateTime(2026, 6, 2);

  testWidgets('behind: shows catch-up tray and hides "Jump to current"', (
    tester,
  ) async {
    final status = _status(
      today: today,
      days: const [
        (dayOffset: -2, completed: false), // missed
        (dayOffset: 0, completed: false), // current
        (dayOffset: 2, completed: false), // upcoming
      ],
    );

    await tester.pumpWidget(_host(status));
    await tester.pumpAndSettle();

    expect(find.text('TEST PLAN'), findsOneWidget);
    expect(find.text('Full schedule'), findsOneWidget);
    // Overdue reading surfaces the gentle catch-up tray with a "TO REVISIT" tag.
    expect(find.text('Catch up at your own pace'), findsOneWidget);
    expect(find.text('TO REVISIT'), findsWidgets);
    // The current reading drives the group anchor.
    expect(find.text('GROUP ANCHOR'), findsOneWidget);
    // No "Jump to current" chip while behind (the tray handles that).
    expect(find.text('Jump to current'), findsNothing);
    expect(find.text('0 of 3 read'), findsOneWidget);
  });

  testWidgets('caught up: shows "Jump to current" chip and "in step" card', (
    tester,
  ) async {
    final status = _status(
      today: today,
      days: const [
        (dayOffset: -2, completed: true), // done
        (dayOffset: 0, completed: true), // current, done
        (dayOffset: 2, completed: false), // upcoming
      ],
    );

    await tester.pumpWidget(_host(status));
    await tester.pumpAndSettle();

    expect(find.text('Jump to current'), findsOneWidget);
    expect(find.text("You're in step with your group."), findsOneWidget);
    expect(find.text('Catch up at your own pace'), findsNothing);
    expect(find.text('2 of 3 read'), findsOneWidget);
  });

  testWidgets('personal: behind shows a quiet inline note, no group chrome', (
    tester,
  ) async {
    final status = _status(
      today: today,
      days: const [
        (dayOffset: -1, completed: false), // missed
        (dayOffset: 0, completed: false), // current
      ],
    );

    await tester.pumpWidget(_host(status, isGroup: false));
    await tester.pumpAndSettle();

    expect(find.text('1 reading to revisit'), findsOneWidget);
    // No group-only chrome on a personal plan.
    expect(find.text('Catch up at your own pace'), findsNothing);
    expect(find.text('GROUP ANCHOR'), findsNothing);
  });

  testWidgets('marking a behind reading keeps press feedback on the marked row',
      (tester) async {
    await tester.pumpWidget(
      _OptimisticHost(
        today: today,
        isGroup: false,
        days: const [
          (dayOffset: -2, completed: false), // behind
          (dayOffset: -1, completed: false), // behind
          (dayOffset: 0, completed: false), // current
        ],
      ),
    );
    await tester.pumpAndSettle();

    final markedRow = find.text('Genesis 1');
    final nextRow = find.text('Genesis 2');
    final markedElement = _rowElement(tester, markedRow);

    await tester.tap(
      find.ancestor(of: markedRow, matching: find.byType(InkWell)),
    );
    await tester.pumpAndSettle();

    // The tapped row keeps its own element — and with it the press state —
    // across the optimistic rebuild that clears the catch-up note.
    expect(identical(_rowElement(tester, markedRow), markedElement), isTrue);
    // The next row never inherits it.
    expect(identical(_rowElement(tester, nextRow), markedElement), isFalse);
  });

  testWidgets(
      'catching up from the tray does not move press state to the next tray row',
      (tester) async {
    await tester.pumpWidget(
      _OptimisticHost(
        today: today,
        days: const [
          (dayOffset: -2, completed: false), // behind
          (dayOffset: -1, completed: false), // behind
          (dayOffset: 0, completed: false), // current
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The tray dots are the only InkResponses in the view.
    final trayDots = find.byType(InkResponse);
    expect(trayDots, findsNWidgets(2));
    final tappedDot = tester.element(trayDots.first);

    await tester.tap(trayDots.first);
    await tester.pumpAndSettle();

    // One behind reading remains; its dot must not have inherited the
    // tapped dot's element.
    expect(trayDots, findsOneWidget);
    expect(identical(tester.element(trayDots), tappedDot), isFalse);
  });

  testWidgets(
      'a marked behind row briefly holds the active highlight, then settles',
      (tester) async {
    await tester.pumpWidget(
      _OptimisticHost(
        today: today,
        isGroup: false,
        days: const [
          (dayOffset: -2, completed: false), // behind
          (dayOffset: -1, completed: false), // behind
          (dayOffset: 0, completed: false), // current
        ],
      ),
    );
    await tester.pumpAndSettle();

    final marked = find.text('Genesis 1');
    final next = find.text('Genesis 2');
    final currentRow = find.text('Genesis 3');
    final activeBackground = _rowBackground(tester, currentRow);
    await tester.tap(find.ancestor(of: marked, matching: find.byType(InkWell)));
    // Pump past the 250ms highlight animation but stay inside the 600ms
    // transient window (pumpAndSettle would run the ink splash past it).
    await tester.pump(const Duration(milliseconds: 300));

    // The marked row takes on the current row's active treatment...
    expect(_rowBackground(tester, marked), activeBackground);
    // ...while the still-behind row below stays quiet.
    expect(_rowBackground(tester, next), isNot(activeBackground));

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // The transient highlight settles back into the completed look.
    expect(_rowBackground(tester, marked), isNot(activeBackground));
  });

  testWidgets('"Jump to current" lands on the current row after catching up',
      (tester) async {
    await tester.pumpWidget(
      _OptimisticHost(
        today: today,
        isGroup: false,
        days: [
          for (var i = 6; i >= 1; i--) (dayOffset: -i, completed: false),
          (dayOffset: 0, completed: false), // current
          (dayOffset: 1, completed: false),
          (dayOffset: 2, completed: false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;

    // Catch up on every behind reading; marking the last one clears the
    // catch-up note and frees the "Jump to current" chip.
    for (var i = 1; i <= 6; i++) {
      await tester.tap(
        find.ancestor(
          of: find.text('Genesis $i'),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Jump to current'), findsOneWidget);

    // Back at the top, the reading that is current now sits below the fold.
    controller.jumpTo(0);
    await tester.pump();
    expect(tester.getRect(find.text('Genesis 7')).top, greaterThan(600));

    await tester.tap(find.text('Jump to current'));
    await tester.pumpAndSettle();

    // The jump reveals the current reading.
    expect(
      tester.getRect(find.text('Genesis 7')).top,
      inInclusiveRange(0, 599),
    );
    expect(controller.offset, greaterThan(0));
  });

  testWidgets(
      'marking yesterday reading as read in group plan does not jump past today reading',
      (tester) async {
    // 30 days so the view is long and scrollable
    final days = [
      for (var i = 10; i >= 1; i--)
        (
          dayOffset: -i,
          completed: i > 1
        ), // Only offset -1 (yesterday) is missed!
      (dayOffset: 0, completed: false), // today (current)
      for (var i = 1; i <= 20; i++) (dayOffset: i, completed: false),
    ];

    await tester.pumpWidget(
      _OptimisticHost(
        today: today,
        isGroup: true,
        days: days,
      ),
    );
    await tester.pumpAndSettle();

    // In group plan with yesterday missed and today unread:
    // Today's reading is Genesis 11 (offset 0). Yesterday is Genesis 10 (offset -1).
    expect(find.text('Catch up at your own pace'), findsOneWidget);
    final todayRowFinder = find.ancestor(
      of: find.text('Genesis 11'),
      matching: find.byType(InkWell),
    );
    expect(todayRowFinder, findsWidgets);

    final todayTopBefore = tester.getRect(todayRowFinder.first).top;

    // Now tap yesterday's reading (either in tray or in schedule). Let's tap yesterday's row in schedule or tray.
    final yesterdayFinder = find.ancestor(
      of: find.text('Genesis 10'),
      matching: find.byType(InkWell),
    );
    await tester.tap(yesterdayFinder.first);
    await tester.pumpAndSettle();

    final todayTopAfter = tester.getRect(todayRowFinder.first).top;

    // Check how much today's row moved relative to the screen or how the scroll offset changed.
    // print('Offset before: $initialOffset, after: ${controller.offset}');
    // print('Today top before: $todayTopBefore, after: $todayTopAfter');

    // If it jumps up past the viewport or jumps drastically:
    expect((todayTopAfter - todayTopBefore).abs(), lessThan(50),
        reason:
            'Today reading jumped by ${(todayTopAfter - todayTopBefore).abs()}px');
  });
}

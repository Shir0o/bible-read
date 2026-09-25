import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/skeleton.dart';
import 'package:bible_read/widgets/skeletons/group_list_skeleton.dart';
import 'package:bible_read/widgets/skeletons/read_log_skeleton.dart';
import 'package:bible_read/widgets/skeletons/read_log_empty_skeleton.dart';
import 'package:bible_read/widgets/skeletons/streak_history_skeleton.dart';
import 'package:bible_read/widgets/skeletons/stat_tiles_skeleton.dart';
import 'package:bible_read/widgets/skeletons/read_through_card_skeleton.dart';
import 'package:bible_read/widgets/skeletons/badge_next_up_skeleton.dart';

void main() {
  group('Skeletons', () {
    testWidgets('GroupListSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GroupListSkeleton())),
      );
      expect(find.byType(GroupListSkeleton), findsOneWidget);
      // Should find multiple skeletons inside (ListView items * lines per item)
      // Just basic smoke test for crashes
    });

    testWidgets('ReadLogSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReadLogSkeleton())),
      );
      expect(find.byType(ReadLogSkeleton), findsOneWidget);
    });

    testWidgets('ReadLogEmptySkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReadLogEmptySkeleton())),
      );
      expect(find.byType(ReadLogEmptySkeleton), findsOneWidget);
    });

    testWidgets('StreakHistorySkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StreakHistorySkeleton())),
      );
      expect(find.byType(StreakHistorySkeleton), findsOneWidget);
    });

    testWidgets('StatTilesSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: StatTilesSkeleton())),
      );
      expect(find.byType(StatTilesSkeleton), findsOneWidget);
      expect(find.byType(Skeleton), findsNWidgets(6));
    });

    testWidgets('ReadThroughCardSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReadThroughCardSkeleton())),
      );
      expect(find.byType(ReadThroughCardSkeleton), findsOneWidget);
      expect(find.text('Times through'), findsOneWidget);
      expect(find.byType(Skeleton), findsNWidgets(6));
    });

    testWidgets('BadgeNextUpSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BadgeNextUpSkeleton())),
      );
      expect(find.byType(BadgeNextUpSkeleton), findsOneWidget);
      expect(find.byType(Skeleton), findsNWidgets(3));
    });
  });
}

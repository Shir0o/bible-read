import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/skeletons/group_list_skeleton.dart';
import 'package:bible_read/widgets/skeletons/read_log_skeleton.dart';
import 'package:bible_read/widgets/skeletons/read_log_empty_skeleton.dart';
import 'package:bible_read/widgets/skeletons/friends_skeleton.dart';
import 'package:bible_read/widgets/skeletons/streak_history_skeleton.dart';

void main() {
  group('Skeletons', () {
    testWidgets('GroupListSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: GroupListSkeleton())));
      expect(find.byType(GroupListSkeleton), findsOneWidget);
      // Should find multiple skeletons inside (ListView items * lines per item)
      // Just basic smoke test for crashes
    });

    testWidgets('ReadLogSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ReadLogSkeleton())));
      expect(find.byType(ReadLogSkeleton), findsOneWidget);
    });

    testWidgets('ReadLogEmptySkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ReadLogEmptySkeleton())));
      expect(find.byType(ReadLogEmptySkeleton), findsOneWidget);
    });

    testWidgets('FriendsSkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: FriendsSkeleton())));
      expect(find.byType(FriendsSkeleton), findsOneWidget);
    });

    testWidgets('StreakHistorySkeleton builds correctly', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: StreakHistorySkeleton())));
      expect(find.byType(StreakHistorySkeleton), findsOneWidget);
    });
  });
}

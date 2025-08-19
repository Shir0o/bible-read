import 'package:bible_read/pages/leaderboard_page.dart';
import 'package:flutter/foundation.dart';

class TestLeaderboardPage extends LeaderboardPage {
  final ValueNotifier<bool> refreshed = ValueNotifier(false);

  TestLeaderboardPage({
    super.key,
    super.firestore,
    super.auth,
    super.friendService,
  });

  @override
  TestLeaderboardPageState createState() => TestLeaderboardPageState();
}

class TestLeaderboardPageState extends LeaderboardPageState {
  @override
  Future<void> refresh() async {
    (widget as TestLeaderboardPage).refreshed.value = true;
  }
}

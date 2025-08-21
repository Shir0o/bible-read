import 'package:bible_read/pages/read_log_page.dart';
import 'package:flutter/foundation.dart';

class TestReadLogPage extends ReadLogPage {
  final ValueNotifier<bool> refreshed = ValueNotifier(false);

  TestReadLogPage({
    super.key,
    super.firestore,
    super.auth,
    required super.onSendLikeNotification,
    required super.onSendCommentNotification,
    super.dateProvider,
  });

  @override
  TestReadLogPageState createState() => TestReadLogPageState();
}

class TestReadLogPageState extends ReadLogPageState {
  @override
  Future<void> refresh() async {
    (widget as TestReadLogPage).refreshed.value = true;
  }
}

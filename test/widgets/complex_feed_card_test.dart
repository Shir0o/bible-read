import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/models/read_log.dart';
import '../helpers/pump_app.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  late StubVibrationService vibrationService;

  setUp(() {
    vibrationService = StubVibrationService();
  });

  testWidgets('FeedCard handles likes without comment UI', (tester) async {
    bool likeCalled = false;

    final log = ReadLog(
      uid: 'user1',
      name: 'Alice',
      liked: false,
      likeNames: [],
      firstReader: false,
      comments: [],
      timestamp: DateTime.now(),
    );

    await tester.pumpApp(
      Scaffold(
        body: SingleChildScrollView(
          child: FeedCard(
            log: log,
            onToggleLike: () async {
              likeCalled = true;
            },
            vibrationService: vibrationService,
          ),
        ),
      ),
    );

    // Verify initial state
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Encourage'), findsNothing);

    // Test Like
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pump();
    expect(likeCalled, isTrue);
    expect(find.text('Comment'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}

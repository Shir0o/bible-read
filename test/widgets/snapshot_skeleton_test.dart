import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/skeleton_loader.dart';
import 'package:bible_read/widgets/skeletons/list_rows_skeleton.dart';

void main() {
  testWidgets('SnapshotSkeleton holds the skeleton for the 1000ms minimum',
      (tester) async {
    final controller = StreamController<String>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(
        home: StreamBuilder<String>(
          stream: controller.stream,
          builder: (context, snapshot) => SnapshotSkeleton<String>(
            snapshot: snapshot,
            skeleton: const ListRowsSkeleton(),
            builder: (context, data) => Text(data),
          ),
        ),
      ),
    );
    expect(find.byType(ListRowsSkeleton), findsOneWidget);

    controller.add('loaded');
    await tester.pump();
    // Data landed, but the skeleton stays for the minimum duration.
    expect(find.byType(ListRowsSkeleton), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ListRowsSkeleton), findsNothing);
    expect(find.text('loaded'), findsOneWidget);
  });
}

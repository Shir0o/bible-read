// Local visual aid for Circle is the Feed (issue #983). CI excludes
// test/goldens/*; regenerate with:
//   flutter test --update-goldens test/goldens/circle_feed_golden_test.dart
import 'dart:io';

import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/read_log_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:network_image_mock/network_image_mock.dart';

import '../helpers/stub_vibration_service.dart';

Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Spectral', [
    'Spectral-Regular.ttf',
    'Spectral-Medium.ttf',
    'Spectral-SemiBold.ttf',
  ]);
  await load('Hanken Grotesk', ['HankenGrotesk-VariableFont_wght.ttf']);
}

/// MockUser falls back to a remote photo; the golden renders the initial.
// ignore: must_be_immutable
class _NoPhotoUser extends MockUser {
  _NoPhotoUser() : super(uid: 'alice', displayName: 'Alice');

  @override
  String? get photoURL => null;
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('Circle Feed golden', (tester) async {
    final today = DateTime(2026, 9, 8);
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: _NoPhotoUser(),
      signedIn: true,
    );
    final members = {
      'alice': 'Alice',
      'ben': 'Ben',
      'eli': 'Eli',
      'mara': 'Mara',
      'sam': 'Sam',
    };
    await firestore
        .collection('groups')
        .doc('g1')
        .set({'name': 'Morning', 'ownerUid': 'alice', 'memberCount': 5});
    for (final m in members.entries) {
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc(m.key)
          .set({'uid': m.key, 'name': m.value, 'role': 'member'});
    }
    Future<void> entry(String uid, int daysAgo, int hour,
        {Map<String, dynamic> extra = const {}}) {
      final key = ReadLogService.dateKeyFor(
          DateTime(today.year, today.month, today.day - daysAgo));
      return firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(key)
          .collection('entries')
          .doc(uid)
          .set({
        'uid': uid,
        'timestamp': Timestamp.fromDate(
            DateTime(today.year, today.month, today.day - daysAgo, hour)),
        ...extra,
      });
    }

    await entry('mara', 0, 8, extra: {
      'sharedReflection': 'The Lord is near to the brokenhearted.',
    });
    await entry('ben', 0, 7);
    await entry('eli', 0, 6);
    await entry('alice', 0, 6);
    await entry('sam', 1, 21, extra: {
      'milestone': {'scope': 'nt', 'lapNumber': 1},
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('badge_log')
        .doc('ben_first_book')
        .set({
      'uid': 'ben',
      'badgeId': 'first_book',
      'dateUnlocked': Timestamp.fromDate(
          DateTime(today.year, today.month, today.day - 2, 9)),
    });

    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: CommunityPage(
          auth: auth,
          firestore: firestore,
          groupService: GroupService(firestore: firestore),
          readingStatusService:
              ReadingStatusService(firestore: firestore, auth: auth),
          vibrationService: const StubVibrationService(),
          dateProvider: () => today,
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });

    await expectLater(
      find.byType(CommunityPage),
      matchesGoldenFile('goldens/circle_feed.png'),
    );
  });
}

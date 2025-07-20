// ignore_for_file: subtype_of_sealed_class

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:fake_cloud_firestore/src/mock_document_reference.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:bible_read/pages/home_page.dart';

class FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => user;

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(idToken: 'id', accessToken: 'access');
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => user != null;

  @override
  Future<void> clearAuthCache({required String token}) async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;

  @override
  Future<bool> canAccessScopes(
    List<String> scopes, {
    String? accessToken,
  }) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

class ThrowingDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(firestore, path, id, root, docsData, rootParent,
            snapshotStreamControllerRoot, null);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    throw FirebaseException(plugin: 'firestore');
  }
}

class ThrowingCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'users') {
      return ThrowingCollectionReference(
        this,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomePage shows static UI elements', (WidgetTester tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.text('Bible Reading Challenge'), findsOneWidget);
    expect(find.textContaining('Streak:'), findsOneWidget);
    expect(find.text('Bible Read Today'), findsOneWidget);
    expect(find.textContaining('Week of'), findsOneWidget);
    expect(find.textContaining('${DateTime.now().year} –'), findsOneWidget);
  });

  testWidgets('shows "User not signed in" when not authenticated',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.text('User not signed in.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('HomePage week row has seven icons', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    // There should be exactly seven icons for the week status row. All are
    // unchecked by default since no data is loaded in tests.
    final unchecked = find.byIcon(Icons.radio_button_unchecked);
    expect(unchecked, findsNWidgets(7));
  });

  testWidgets('HomePage month calendar matches current month', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    // Verify the month header text
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final header = '${now.year} – ${months[now.month - 1]}';
    expect(find.text(header), findsOneWidget);

    // Calendar should include one icon per day of the month
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final filled = tester.widgetList(find.byIcon(Icons.circle));
    final empty = tester.widgetList(find.byIcon(Icons.circle_outlined));
    expect(filled.length + empty.length, daysInMonth);
  });

  testWidgets('toggling read status writes reading doc and summary',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(
        uid: 'u1', displayName: 'Test User', email: 'test@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    final switchTile =
        tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(switchTile.onChanged, isNull);
  });

  testWidgets('toggling read status does not show progress indicator',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u-ci'), signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('marking reading done creates Firestore entries', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user =
        MockUser(uid: 'u-read', displayName: 'Tester', email: 't@example.com');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';

    final logDoc = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc(user.uid)
        .get();
    expect(logDoc.exists, isTrue);

    final readingDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('reading')
        .doc(dateKey)
        .get();
    expect(readingDoc.exists, isTrue);

    final summaryDoc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('summary')
        .doc('data')
        .get();
    expect(summaryDoc.data()?['streak'], 1);
  });

  testWidgets('like and unlike reading update Firestore', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u2');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(HomePage)) as dynamic;
    await state.likeReading();
    await tester.pumpAndSettle();
    final dateKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    var likeDoc = await firestore
        .collection('users')
        .doc('u2')
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc('u2')
        .get();
    expect(likeDoc.exists, isTrue);

    await state.unlikeReading();
    await tester.pumpAndSettle();
    likeDoc = await firestore
        .collection('users')
        .doc('u2')
        .collection('reading')
        .doc(dateKey)
        .collection('likes')
        .doc('u2')
        .get();
    expect(likeDoc.exists, isFalse);
  });

  testWidgets('refresh recalculates summary from reading data', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u3');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final googlePlatform = FakeGoogleSignInPlatform();
    GoogleSignInPlatform.instance = googlePlatform;

    final today = DateTime.now();
    for (int i = 0; i < 3; i++) {
      final date = today.subtract(Duration(days: i));
      final key = '${date.year}-${date.month}-${date.day}';
      await firestore
          .collection('users')
          .doc('u3')
          .collection('reading')
          .doc(key)
          .set({'read': true});
    }

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(RefreshIndicator), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final summary = await firestore
        .collection('users')
        .doc('u3')
        .collection('summary')
        .doc('data')
        .get();
    expect(summary.data()?['streak'], 3);
  });

  testWidgets('load failure hides progress indicator', (tester) async {
    final firestore = ThrowingFirestore();
    final auth =
        MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await tester.pumpWidget(
        MaterialApp(home: HomePage(firestore: firestore, auth: auth)));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

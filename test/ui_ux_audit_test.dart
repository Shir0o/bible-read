// UI/UX audit of the primary app shell.
//
// Pumps the real MainPage / app shell at three device + text-scale variants,
// asserts there are no RenderFlex overflows, runs the Android tap-target and
// text-contrast accessibility guidelines (reporting, not failing, when they are
// not met), and captures reference screenshots.
//
// Generate the reference PNGs with:
//   flutter test --update-goldens test/ui_ux_audit_test.dart
//
// The screenshots are platform-dependent (macOS and Linux rasterise fonts
// differently), so they are only written with --update-goldens and are not
// compared on CI, matching the convention in test/goldens/README.md.

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/app_nav_bar.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/fake_google_sign_in_platform.dart';
import 'helpers/mock_sqflite.dart';
import 'helpers/path_provider_mock.dart';
import 'helpers/stub_vibration_service.dart';

/// One device / accessibility configuration to audit.
class _AuditVariant {
  const _AuditVariant({
    required this.name,
    required this.size,
    required this.textScale,
    required this.brightness,
  });

  final String name;
  final Size size;
  final double textScale;
  final Brightness brightness;

  ThemeMode get themeMode =>
      brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
}

const _phoneLight = _AuditVariant(
  name: 'phone_light',
  size: Size(390, 844),
  textScale: 1.0,
  brightness: Brightness.light,
);

const _phoneDark = _AuditVariant(
  name: 'phone_dark',
  size: Size(390, 844),
  textScale: 1.0,
  brightness: Brightness.dark,
);

const _smallLargeFont = _AuditVariant(
  name: 'small_large_font',
  size: Size(320, 568),
  textScale: 1.6,
  brightness: Brightness.light,
);

const _variants = [_phoneLight, _phoneDark, _smallLargeFont];

/// Goldens need the real bundled fonts; the default test font draws boxes.
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

/// MainPage's ConnectivityService checks the platform on creation; without a
/// handler the headless test throws MissingPluginException.
void _setupConnectivityMock() {
  const methodChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );
  const eventChannel = EventChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (call) async {
    if (call.method == 'check') return <String>['wifi'];
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    eventChannel,
    MockStreamHandler.inline(
      onListen: (arguments, events) => events.success(<String>['wifi']),
    ),
  );
}

class _FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async =>
      null;
}

/// MockUser defaults to a remote photo; force the initial-letter avatar so the
/// screenshots show a face instead of a blank loaded-image placeholder.
// ignore: must_be_immutable
class _NoPhotoUser extends MockUser {
  _NoPhotoUser() : super(uid: 'u1', displayName: 'Ada Reader');

  @override
  String? get photoURL => null;
}

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Seeds a reader with a little history so the shell renders real content
/// instead of empty placeholders.
Future<void> _seed(FakeFirebaseFirestore firestore) async {
  final now = DateTime.now();
  await firestore.collection('users').doc('u1').set({
    'displayName': 'Ada Reader',
    'email': 'ada@example.com',
    'createdAt': now,
  });
  await firestore
      .collection('users')
      .doc('u1')
      .collection('summary')
      .doc('data')
      .set({
    'streak': 12,
    'totalReadDays': 42,
    'pastWeekReadDates': [
      for (var i = 1; i <= 5; i++) _dateKey(now.subtract(Duration(days: i))),
    ],
    'graceCreditsAvailable': 1,
  });
  await firestore
      .collection('users')
      .doc('u1')
      .collection('reading')
      .doc(_dateKey(now))
      .set({'read': true});
}

/// Pumps the app shell for [variant] and settles it, dismissing the daily
/// check-in sheet so the audit sees the primary screen.
Future<void> _pumpApp(WidgetTester tester, _AuditVariant variant) async {
  tester.view.physicalSize = variant.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final firestore = FakeFirebaseFirestore();
  await _seed(firestore);
  final auth = MockFirebaseAuth(
    mockUser: _NoPhotoUser(),
    signedIn: true,
  );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.appTheme(AppTheme.designLightScheme),
      darkTheme: AppTheme.appTheme(AppTheme.designDarkScheme),
      themeMode: variant.themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: variant.size,
            devicePixelRatio: 1.0,
            textScaler: TextScaler.linear(variant.textScale),
            platformBrightness: variant.brightness,
          ),
          child: child!,
        );
      },
      home: MainPage(
        auth: auth,
        firestore: firestore,
        messaging: _FakeFirebaseMessaging(),
        vibrationService: const StubVibrationService(),
      ),
    ),
  );

  await _settle(tester);
}

/// The home streams complete through short fallback timers, so advance fake
/// time before falling back to [pumpAndSettle] for the remaining animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) break;
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 100));

  final checkIn = find.byType(CheckInPage);
  if (checkIn.evaluate().isNotEmpty) {
    tester.widget<CheckInPage>(checkIn).onClose();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }
}

/// Fails the test if the widget tree reported any exception, including the
/// RenderFlex overflow errors this audit exists to catch.
void _expectNoOverflow(WidgetTester tester, String label) {
  final errors = <Object>[];
  Object? error = tester.takeException();
  while (error != null) {
    errors.add(error);
    error = tester.takeException();
  }
  expect(
    errors,
    isEmpty,
    reason: '$label reported ${errors.length} widget-tree exception(s):\n'
        '${errors.join('\n\n')}',
  );
}

/// Runs the accessibility guidelines, reporting failures without failing the
/// run so drift stays visible in the audit log.
Future<void> _checkGuidelines(WidgetTester tester, String label) async {
  final guidelines = <String, AccessibilityGuideline>{
    'androidTapTargetGuideline': androidTapTargetGuideline,
    'textContrastGuideline': textContrastGuideline,
  };
  for (final entry in guidelines.entries) {
    try {
      await expectLater(tester, meetsGuideline(entry.value));
    } on TestFailure catch (failure) {
      debugPrint(
        'UI/UX audit [$label] ${entry.key} not satisfied:\n$failure',
      );
    }
  }
}

/// Captures [name] under test/goldens when goldens are being updated.
///
/// Screenshots are platform-dependent (macOS and Linux rasterise fonts
/// differently), so they are regenerated on demand with --update-goldens
/// rather than compared on CI, matching test/goldens/README.md.
Future<void> _capture(WidgetTester tester, String name) async {
  if (!autoUpdateGoldenFiles) {
    debugPrint(
      'UI/UX audit: skipping goldens/$name.png '
      '(run with --update-goldens to create it).',
    );
    return;
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppNavBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  // The app shell can reach cached_network_image through avatars, which needs
  // path_provider and sqflite wired for the headless test environment.
  setupPathProviderMocks();
  setupSqfliteMock();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    await Firebase.initializeApp();
    await _loadAppFonts();
  });

  setUp(() {
    // setMockStreamHandler registers a teardown, so it must run per test.
    _setupConnectivityMock();
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  for (final variant in _variants) {
    testWidgets('${variant.name}: no overflow + accessibility audit', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await mockNetworkImagesFor(() async {
          await _pumpApp(tester, variant);

          // Zero RenderFlex overflows (and no other widget-tree errors).
          _expectNoOverflow(tester, variant.name);

          // Advisory accessibility guidelines.
          await _checkGuidelines(tester, variant.name);

          // Reference screenshot for the settled primary screen.
          await _capture(tester, 'bible_read_${variant.name}');
        });
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('phone click-through: tabs, menu sheet, settings',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mockNetworkImagesFor(() async {
        await _pumpApp(tester, _phoneLight);
        await _capture(tester, 'bible_read_step1_today');

        // Bottom navigation: Circle.
        await _tapTab(tester, 'Circle');
        expect(find.text('No one here yet'), findsOneWidget);
        _expectNoOverflow(tester, 'step2 Circle');
        await _capture(tester, 'bible_read_step2_circle_tab');

        // Bottom navigation: Path.
        await _tapTab(tester, 'Path');
        _expectNoOverflow(tester, 'step3 Path');
        await _capture(tester, 'bible_read_step3_path_tab');

        // Back to Today, then open the avatar menu sheet.
        await _tapTab(tester, 'Today');
        await tester.tap(find.byTooltip('Open menu'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.text('Settings'), findsOneWidget);
        _expectNoOverflow(tester, 'step4 menu sheet');
        await _checkGuidelines(tester, 'step4 menu sheet');
        await _capture(tester, 'bible_read_step4_menu_sheet');

        // Primary action inside the menu: open Settings.
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(SettingsPage), findsOneWidget);
        _expectNoOverflow(tester, 'step5 settings');
        await _capture(tester, 'bible_read_step5_settings');
      });
    } finally {
      semantics.dispose();
    }
  });
}

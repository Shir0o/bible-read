import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:bible_read/services/reflection_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReflectionService service;
  const uid = 'test-user';
  const dateKey = '2026-07-16';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = ReflectionService(firestore: firestore);
  });

  test('fetchReflection returns null if no document exists', () async {
    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection, isNull);
  });

  test('saveReflection then fetchReflection round-trips the text', () async {
    await service.saveReflection(uid, dateKey, 'Dead to sin, alive to God.');

    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection?.text, 'Dead to sin, alive to God.');
  });

  test('saveReflection trims surrounding whitespace', () async {
    await service.saveReflection(uid, dateKey, '  A single line.  ');

    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection?.text, 'A single line.');
  });

  test(
    'saveReflection with blank text deletes any existing reflection',
    () async {
      await service.saveReflection(uid, dateKey, 'First draft');
      expect((await service.fetchReflection(uid, dateKey))?.text, isNotNull);

      await service.saveReflection(uid, dateKey, '   ');

      expect(await service.fetchReflection(uid, dateKey), isNull);
    },
  );

  test('deleteReflection removes a saved reflection', () async {
    await service.saveReflection(uid, dateKey, 'Something worth keeping');
    await service.deleteReflection(uid, dateKey);

    expect(await service.fetchReflection(uid, dateKey), isNull);
  });

  test('saveReflection overwrites a previous entry for the same day', () async {
    await service.saveReflection(uid, dateKey, 'First draft');
    await service.saveReflection(uid, dateKey, 'Revised thought');

    final reflection = await service.fetchReflection(uid, dateKey);
    expect(reflection?.text, 'Revised thought');
  });

  test('reflections for different days are independent', () async {
    await service.saveReflection(uid, '2026-07-15', 'Yesterday');
    await service.saveReflection(uid, '2026-07-16', 'Today');

    expect(
      (await service.fetchReflection(uid, '2026-07-15'))?.text,
      'Yesterday',
    );
    expect((await service.fetchReflection(uid, '2026-07-16'))?.text, 'Today');
  });
}

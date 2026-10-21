import 'package:bible_read/services/friend_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const code = '7QK4M2PX';
  const groupCode = 'ABC234';

  group('linkFor', () {
    test('builds an https link carrying the code', () {
      final link = FriendInvite.linkFor(code);

      expect(link, startsWith('https://'));
      expect(link, contains('code=$code'));
      expect(Uri.parse(link).queryParameters['code'], code);
    });

    test('builds an https link carrying a group code', () {
      final link = FriendInvite.linkFor(groupCode);

      expect(link, startsWith('https://'));
      expect(link, contains('code=$groupCode'));
      expect(Uri.parse(link).queryParameters['code'], groupCode);
    });
  });

  group('codeFrom', () {
    test('reads the code from a shared https link', () {
      final uri = Uri.parse(FriendInvite.linkFor(code));

      expect(FriendInvite.codeFrom(uri), code);
    });

    test('reads a group code from a shared https link', () {
      final uri = Uri.parse(FriendInvite.linkFor(groupCode));

      expect(FriendInvite.codeFrom(uri), groupCode);
    });

    test('reads the code from a custom-scheme friend link', () {
      // The form the hosted landing page opens (docs/f/index.html).
      final uri = Uri.parse('bibleread://friend?code=$code');

      expect(FriendInvite.codeFrom(uri), code);
    });

    test('reads a group code from a custom-scheme group link', () {
      final uri = Uri.parse('bibleread://group?code=$groupCode');

      expect(FriendInvite.codeFrom(uri), groupCode);
    });

    test('normalises a lowercase code in the link', () {
      final uri = Uri.parse(FriendInvite.linkFor(code).toLowerCase());

      expect(FriendInvite.codeFrom(uri), code);
    });

    test('returns null for an unrelated link', () {
      expect(
        FriendInvite.codeFrom(Uri.parse('https://example.com/f?code=$code')),
        isNull,
      );
    });

    test('returns null when the code is malformed', () {
      expect(
        FriendInvite.codeFrom(Uri.parse(FriendInvite.linkFor('NOPE'))),
        isNull,
      );
    });

    test('returns null when there is no code at all', () {
      expect(
        FriendInvite.codeFrom(
            Uri.parse('https://shir0o.github.io/bible-read/f')),
        isNull,
      );
    });
  });

  group('codeFromText', () {
    test('reads a raw code', () {
      expect(FriendInvite.codeFromText(' ${code.toLowerCase()} '), code);
    });

    test('reads a raw group code', () {
      expect(
          FriendInvite.codeFromText(' ${groupCode.toLowerCase()} '), groupCode);
    });

    test('reads a pasted https link', () {
      expect(FriendInvite.codeFromText(FriendInvite.linkFor(code)), code);
    });

    test('reads a pasted group https link', () {
      expect(FriendInvite.codeFromText(FriendInvite.linkFor(groupCode)),
          groupCode);
    });

    test('returns null for prose that is not a code', () {
      expect(FriendInvite.codeFromText('hello there'), isNull);
    });
  });
}

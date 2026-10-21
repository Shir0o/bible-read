import 'friend_service.dart';
import 'join_code_service.dart';

/// The invite link a reader sends to add someone as a Friend (ADR-0012 V3).
///
/// The link carries only the friend code — the inviter's name and photo are
/// resolved on open through [FriendService]. The custom-scheme form opens the
/// app directly; the https form also lands on a hosted page for a recipient
/// who does not have the app yet.
abstract final class FriendInvite {
  /// Custom URL scheme that the app registers to receive invites.
  static const String scheme = 'bibleread';

  /// Host used inside the custom-scheme link for group invites.
  static const String groupAppHost = 'group';

  /// Host used inside the custom-scheme link for friend invites.
  static const String friendAppHost = 'friend';

  /// Host that serves the invite landing page.
  static const String webHost = 'shir0o.github.io';

  /// Path of the invite landing page on [webHost].
  static const String webPath = '/bible-read/f';

  /// The shareable https link carrying [code].
  static String linkFor(String code) {
    final normalized = FriendService.normalize(code);
    return Uri.https(webHost, webPath, {'code': normalized}).toString();
  }

  /// Extracts an invite code from an incoming [uri], or null when [uri] is not
  /// an invite link or the code it carries is malformed.
  static String? codeFrom(Uri uri) {
    final isWebLink = uri.scheme == 'https' &&
        uri.host == webHost &&
        uri.path.startsWith(webPath);
    final isAppLink = uri.scheme == scheme;
    if (!isWebLink && !isAppLink) return null;

    final candidate = uri.queryParameters['code'] ??
        (uri.pathSegments.isEmpty ? null : uri.pathSegments.last);
    if (candidate == null) return null;

    final code = FriendService.normalize(candidate);
    final isFriend = code.length == FriendService.codeLength &&
        FriendService.looksLikeCode(code);
    final isGroup = code.length == JoinCodeService.codeLength &&
        code.split('').every(JoinCodeService.alphabet.contains);
    return (isFriend || isGroup) ? code : null;
  }

  /// Extracts an invite code from pasted [raw] text: an invite link (any form)
  /// or a bare code. Returns null when [raw] is neither.
  static String? codeFromText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return codeFrom(uri);

    final code = FriendService.normalize(trimmed);
    final isFriend = code.length == FriendService.codeLength &&
        FriendService.looksLikeCode(code);
    final isGroup = code.length == JoinCodeService.codeLength &&
        code.split('').every(JoinCodeService.alphabet.contains);
    return (isFriend || isGroup) ? code : null;
  }
}

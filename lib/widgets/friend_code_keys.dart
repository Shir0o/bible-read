import 'package:flutter/widgets.dart';

/// Widget keys for the friend-code screens.
abstract final class FriendCodeKeys {
  static const codeText = Key('friend_code_text');
  static const copyButton = Key('friend_code_copy');
  static const shareButton = Key('friend_code_share');
  static const resetButton = Key('friend_code_reset');
  static const enterCodeButton = Key('friend_code_enter');

  static const previewCard = Key('friend_code_preview');
  static const confirmButton = Key('friend_code_confirm');
}

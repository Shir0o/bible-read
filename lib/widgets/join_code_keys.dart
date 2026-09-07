import 'package:flutter/widgets.dart';

/// Widget keys for the join-code screens (Share code, Join by code).
///
/// These exist so tests can find controls by identity rather than by label.
abstract final class JoinCodeKeys {
  static const codeField = Key('join_code_field');
  static const findButton = Key('join_code_find');
  static const errorText = Key('join_code_error');
  static const previewCard = Key('join_code_preview');
  static const memberNote = Key('join_code_member_note');
  static const confirmButton = Key('join_code_confirm');

  static const codeText = Key('share_code_text');
  static const copyButton = Key('share_code_copy');
  static const regenerateButton = Key('share_code_regenerate');
}

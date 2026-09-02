import 'package:flutter/widgets.dart';

/// Widget keys for the group plan configurator.
///
/// These exist so tests can find controls by identity rather than by label.
/// The screens they cover were previously asserted entirely through visible
/// text, which made every copy change a test failure.
abstract final class GroupPlanKeys {
  static const nameField = Key('group_plan_name_field');
  static const bookSearchField = Key('group_plan_book_search');
  static const startsAtCard = Key('group_plan_starts_at_card');
  static const startRefText = Key('group_plan_start_ref');
  static const changeStartButton = Key('group_plan_change_start');
  static const skipNote = Key('group_plan_skip_note');

  static const startSheet = Key('group_plan_start_sheet');
  static const startSheetCta = Key('group_plan_start_sheet_cta');
  static const startSheetClose = Key('group_plan_start_sheet_close');

  static const paceModeSegment = Key('group_plan_pace_mode');
  static const chaptersPerDayStepper = Key('group_plan_chapters_per_day');
  static const endDateButton = Key('group_plan_end_date');

  static const bookBoundarySwitch = Key('group_plan_book_boundary');
  static const seeAllDaysButton = Key('group_plan_see_all_days');
  static const evenItOutButton = Key('group_plan_even_it_out');
  static const submitButton = Key('group_plan_submit');
  static const validationMessage = Key('group_plan_validation');

  static const rebuildConfirmDialog = Key('group_plan_rebuild_dialog');
  static const rebuildConfirmAccept = Key('group_plan_rebuild_accept');

  static Key bookChip(String book) => Key('group_plan_book_chip_$book');
  static Key removeBook(String book) => Key('group_plan_remove_book_$book');
  static Key weekday(int weekday) => Key('group_plan_weekday_$weekday');
  static Key weekdayPreset(String name) => Key('group_plan_preset_$name');
  static Key startSheetBookPill(String book) =>
      Key('group_plan_start_pill_$book');
  static Key startSheetChapter(int chapter) =>
      Key('group_plan_start_chapter_$chapter');
  static Key dayRow(int index) => Key('group_plan_day_row_$index');
  static Key dayStepperInc(int index) => Key('group_plan_day_inc_$index');
  static Key dayStepperDec(int index) => Key('group_plan_day_dec_$index');
  static Key daySetTag(int index) => Key('group_plan_day_set_$index');
}

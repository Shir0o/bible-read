import 'package:flutter/material.dart';

import '../services/feedback_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';
import '../widgets/feedback_form.dart';

export '../widgets/feedback_form.dart' show FeedbackTab;

/// Page allowing users to submit bug reports or feature requests.
class FeedbackPage extends StatelessWidget {
  /// Creates a [FeedbackPage].
  FeedbackPage({
    super.key,
    this.initialTab = FeedbackTab.bug,
    FeedbackService? feedbackService,
    VibrationService? vibrationService,
    this.parentMessenger,
  }) : feedbackService = feedbackService ?? FeedbackService(),
       vibrationService = vibrationService ?? const VibrationService();

  /// Tab displayed when the page opens.
  final FeedbackTab initialTab;

  /// Service used to submit feedback entries.
  final FeedbackService feedbackService;

  /// Service used to provide consistent haptic feedback in the form.
  final VibrationService vibrationService;

  /// Messenger from the calling page used to display success snack bars once
  /// the feedback flow completes.
  final ScaffoldMessengerState? parentMessenger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Feedback',
            style: CommonStyles.appBarTitleText(colorScheme),
          ),
          backgroundColor: colorScheme.surface,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Report a Bug'),
              Tab(text: 'Request a Feature'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            FeedbackForm(
              tab: FeedbackTab.bug,
              parentMessenger: parentMessenger,
              vibrationService: vibrationService,
              onSubmit: (title, description, steps) {
                return feedbackService.submitBugReport(
                  title: title,
                  description: description,
                  reproductionSteps: steps,
                );
              },
            ),
            FeedbackForm(
              tab: FeedbackTab.feature,
              parentMessenger: parentMessenger,
              vibrationService: vibrationService,
              onSubmit: (title, description, steps) {
                return feedbackService.submitFeatureRequest(
                  title: title,
                  description: description,
                  reproductionSteps: steps,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

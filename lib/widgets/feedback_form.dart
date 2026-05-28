import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/error_logger.dart';
import '../services/vibration_service.dart';
import 'animated_action_button.dart';
import 'common_styles.dart';
import 'vibration_button.dart';

/// Form types supported by [FeedbackForm].
enum FeedbackTab { bug, feature }

/// Shared feedback form used for bug reports and feature requests.
class FeedbackForm extends StatefulWidget {
  /// Creates a [FeedbackForm].
  const FeedbackForm({
    super.key,
    required this.tab,
    required this.onSubmit,
    required this.parentMessenger,
    VibrationService? vibrationService,
  }) : vibrationService = vibrationService ?? const VibrationService();

  /// The type of feedback the form is collecting.
  final FeedbackTab tab;

  /// Called when the user submits the form with validated data.
  final Future<void> Function(
    String title,
    String description,
    String? reproductionSteps,
  )
  onSubmit;

  /// Messenger used to display success snack bars once the route closes.
  final ScaffoldMessengerState? parentMessenger;

  /// Service used to provide consistent haptic feedback.
  final VibrationService vibrationService;

  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<FeedbackForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _stepsController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.addListener(_onTextChanged);
    _stepsController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_onTextChanged);
    _stepsController.removeListener(_onTextChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  String get _formPrefix => widget.tab == FeedbackTab.bug ? 'bug' : 'feature';

  String get _submitLabel => widget.tab == FeedbackTab.bug
      ? 'Submit Bug Report'
      : 'Submit Feature Request';

  String get _successMessage => widget.tab == FeedbackTab.bug
      ? 'Bug report submitted! Thank you for letting us know.'
      : 'Feature request submitted! Thanks for the suggestion.';

  String get _errorMessage => widget.tab == FeedbackTab.bug
      ? 'Failed to submit bug report. Please try again.'
      : 'Failed to submit feature request. Please try again.';

  String get _titleLabel =>
      widget.tab == FeedbackTab.bug ? 'Bug title' : 'Feature title';

  String get _descriptionLabel => widget.tab == FeedbackTab.bug
      ? 'What happened?'
      : 'What would you like to see?';

  String get _stepsLabel => widget.tab == FeedbackTab.bug
      ? 'Reproduction steps (optional)'
      : 'Additional context (optional)';

  Future<void> _handleSubmit() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
    });
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final steps = _stepsController.text.trim();
    final reproductionSteps = steps.isEmpty ? null : steps;

    try {
      await widget.onSubmit(title, description, reproductionSteps);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final snackBar = SnackBar(content: Text(_successMessage));
      if (widget.parentMessenger != null) {
        widget.parentMessenger!.showSnackBar(snackBar);
      } else {
        messenger.showSnackBar(snackBar);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to submit feedback: $error');
      }
      ErrorLogger.log(error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: CommonStyles.backgroundDecoration(
        Theme.of(context).colorScheme,
      ),
      width: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: ValueKey('${_formPrefix}TitleField'),
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(labelText: _titleLabel),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a title.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: ValueKey('${_formPrefix}DescriptionField'),
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: _descriptionLabel,
                      suffixIcon: _descriptionController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear description',
                              onPressed: _descriptionController.clear,
                            )
                          : null,
                    ),
                    minLines: 3,
                    maxLines: 6,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please describe the ${widget.tab == FeedbackTab.bug ? 'bug' : 'feature'}.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: ValueKey('${_formPrefix}StepsField'),
                    controller: _stepsController,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: _stepsLabel,
                      suffixIcon: _stepsController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear steps',
                              onPressed: _stepsController.clear,
                            )
                          : null,
                    ),
                    minLines: 2,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 24),
                  AnimatedActionButton(
                    key: ValueKey('${_formPrefix}SubmitButton'),
                    onPressed: _handleSubmit,
                    isLoading: _isSubmitting,
                    vibrationService: widget.vibrationService,
                    child: Text(_submitLabel),
                  ),
                  const SizedBox(height: 12),
                  VibrationButton(
                    key: ValueKey('${_formPrefix}CancelButton'),
                    vibrationService: widget.vibrationService,
                    onPressed: () {
                      Navigator.of(context).maybePop();
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

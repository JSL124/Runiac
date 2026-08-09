import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../data/flutterfire_submit_feedback_callable.dart';

enum FeedbackCategory {
  bug(label: 'Bug', backendValue: 'bug'),
  planIssue(label: 'Plan issue', backendValue: 'plan issue'),
  billing(label: 'Billing', backendValue: 'billing'),
  other(label: 'Other', backendValue: 'other');

  const FeedbackCategory({required this.label, required this.backendValue});

  final String label;
  final String backendValue;
}

/// Account → Feedback. Lets a signed-in runner report a bug or share a
/// suggestion. The server owns validation and rate limiting; this screen
/// only collects the category/message and forwards them to the
/// `submitFeedback` callable, then reads back its trusted response.
class FeedbackScreen extends StatefulWidget {
  FeedbackScreen({SubmitFeedbackCallable? callable, super.key})
    : callable = callable ?? FlutterFireSubmitFeedbackCallable();

  final SubmitFeedbackCallable callable;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final TextEditingController _messageController = TextEditingController();
  FeedbackCategory? _selectedCategory;
  bool _isSubmitting = false;

  bool get _canSubmit {
    return !_isSubmitting &&
        _selectedCategory != null &&
        _messageController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _handleCategorySelected(FeedbackCategory category) {
    setState(() => _selectedCategory = category);
  }

  void _handleMessageChanged(String value) {
    setState(() {});
  }

  Future<void> _handleSubmit() async {
    final category = _selectedCategory;
    if (!_canSubmit || category == null) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.callable.call(<String, Object?>{
        'category': category.backendValue,
        'message': _messageController.text,
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')),
        );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is SubmitFeedbackException
          ? error.userMessage
          : 'Something went wrong. Please try again.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Feedback',
              tooltip: 'Back to Account',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Container(
                  key: const ValueKey<String>('feedbackFormCard'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: RuniacColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: RuniacColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What kind of feedback is this?',
                        style: TextStyle(
                          color: RuniacColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FeedbackCategoryChips(
                        selectedCategory: _selectedCategory,
                        onSelected: _handleCategorySelected,
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Tell us more',
                        style: TextStyle(
                          color: RuniacColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>('feedbackMessageField'),
                        controller: _messageController,
                        onChanged: _handleMessageChanged,
                        minLines: 5,
                        maxLines: 8,
                        maxLength: 2000,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText:
                              'Describe the bug or share your suggestion...',
                          filled: true,
                          fillColor: RuniacColors.innerTileSurface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: RuniacColors.border,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                              color: RuniacColors.primaryBlue,
                              width: 1.4,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: const ValueKey<String>('feedbackSubmitButton'),
                          onPressed: _canSubmit ? _handleSubmit : null,
                          style: RuniacButtonStyles.primary(
                            disabledBackgroundColor:
                                RuniacColors.disabledButtonBackground,
                            disabledForegroundColor:
                                RuniacColors.disabledButtonForeground,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      RuniacColors.white,
                                    ),
                                  ),
                                )
                              : const Text('Submit feedback'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCategoryChips extends StatelessWidget {
  const _FeedbackCategoryChips({
    required this.selectedCategory,
    required this.onSelected,
  });

  final FeedbackCategory? selectedCategory;
  final ValueChanged<FeedbackCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in FeedbackCategory.values)
          ChoiceChip(
            key: ValueKey<String>('feedbackCategoryChip_${category.name}'),
            label: Text(category.label),
            selected: selectedCategory == category,
            onSelected: (_) => onSelected(category),
            backgroundColor: RuniacColors.white,
            selectedColor: RuniacColors.sectionSurfaceStrong,
            side: BorderSide(
              color: selectedCategory == category
                  ? RuniacColors.primaryBlue
                  : RuniacColors.border,
            ),
            labelStyle: TextStyle(
              color: selectedCategory == category
                  ? RuniacColors.primaryBlue
                  : RuniacColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

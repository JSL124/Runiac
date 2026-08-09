part of 'cool_down_guide_screen.dart';

class _PhaseCopy {
  const _PhaseCopy({
    required this.stepTitle,
    required this.helper,
    required this.tips,
    required this.completeTitle,
    required this.completeHelper,
    required this.bottomLabel,
    required this.completeCta,
    required this.icon,
  });

  final String stepTitle;
  final String helper;
  final List<String> tips;
  final String completeTitle;
  final String completeHelper;
  final String bottomLabel;
  final String completeCta;
  final IconData icon;

  _StepContent get runningContent {
    return _StepContent(icon: icon, title: stepTitle, helper: helper);
  }

  _StepContent get completeContent {
    return _StepContent(
      icon: Icons.check_rounded,
      title: completeTitle,
      helper: completeHelper,
    );
  }
}

class _StepContent {
  const _StepContent({
    required this.icon,
    required this.title,
    required this.helper,
  });

  final IconData icon;
  final String title;
  final String helper;
}

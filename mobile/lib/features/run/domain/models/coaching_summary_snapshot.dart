enum CoachingSummarySource {
  ruleBased,
  aiGenerated;

  String get sectionTitle {
    return switch (this) {
      CoachingSummarySource.ruleBased => 'Coaching Summary',
      CoachingSummarySource.aiGenerated => 'AI Coaching Summary',
    };
  }
}

enum CoachingInterpretationId {
  lowDataInterpretation,
  shortValidInterpretation,
  basicCompletionInterpretation,
  pacingAwarenessInterpretation,
  paceControlInterpretation,
  steadyEffortInterpretation,
  scalarOnlyInterpretation,
  dataQualityFallbackInterpretation,
}

class CoachingSummarySnapshot {
  const CoachingSummarySnapshot({
    required CoachingSummarySource source,
    CoachingInterpretationId interpretationId =
        CoachingInterpretationId.basicCompletionInterpretation,
    required String headline,
    required String message,
    required String nextAction,
    List<String> bullets = const [],
  }) : this._(
         source: source,
         interpretationId: interpretationId,
         headline: headline,
         message: message,
         nextAction: nextAction,
         bullets: bullets,
       );

  const CoachingSummarySnapshot._({
    required this.source,
    required this.interpretationId,
    required this.headline,
    required this.message,
    required this.nextAction,
    required this._bullets,
  });

  final CoachingSummarySource source;
  final CoachingInterpretationId interpretationId;
  final String headline;
  final String message;
  final List<String> _bullets;
  final String nextAction;

  String get sectionTitle => source.sectionTitle;
  List<String> get bullets => List.unmodifiable(_bullets);
}

enum MatchLevel { exact, fuzzy, none }

class MatchResult {
  final String answer;
  final String matchedQuestion;
  final double confidence;
  final MatchLevel level;
  final String? explanation;
  final List<CandidateItem> candidates;

  const MatchResult({
    required this.answer,
    required this.matchedQuestion,
    required this.confidence,
    required this.level,
    this.explanation,
    this.candidates = const [],
  });

  factory MatchResult.empty() => const MatchResult(
        answer: '',
        matchedQuestion: '',
        confidence: 0.0,
        level: MatchLevel.none,
      );

  String get confidencePercent => '${(confidence * 100).toInt()}%';
}

class CandidateItem {
  final String question;
  final String answer;
  final String? explanation;
  final double score;

  const CandidateItem({
    required this.question,
    required this.answer,
    this.explanation,
    required this.score,
  });

  String get scorePercent => '${(score * 100).toInt()}%';
}

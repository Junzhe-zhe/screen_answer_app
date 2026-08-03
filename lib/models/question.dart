class Question {
  final String id;
  final String bankId;
  final String rawText;
  final String preprocessedText;
  final String answer;
  final String? explanation;
  final DateTime createdAt;

  const Question({
    required this.id,
    required this.bankId,
    required this.rawText,
    required this.preprocessedText,
    required this.answer,
    this.explanation,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'bank_id': bankId,
        'raw_text': rawText,
        'preprocessed_text': preprocessedText,
        'answer': answer,
        'explanation': explanation,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

class RecognitionHistory {
  final String id;
  final String ocrText;
  final String? matchedQuestion;
  final String? matchedAnswer;
  final double? confidence;
  final String? matchLevel;
  final String? bankId;
  final DateTime timestamp;

  const RecognitionHistory({
    required this.id,
    required this.ocrText,
    this.matchedQuestion,
    this.matchedAnswer,
    this.confidence,
    this.matchLevel,
    this.bankId,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'ocr_text': ocrText,
        'matched_question': matchedQuestion,
        'matched_answer': matchedAnswer,
        'confidence': confidence,
        'match_level': matchLevel,
        'bank_id': bankId,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}

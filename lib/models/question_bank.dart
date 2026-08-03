class QuestionBank {
  final String id;
  final String name;
  final String? sourceFile;
  final int questionCount;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QuestionBank({
    required this.id,
    required this.name,
    this.sourceFile,
    this.questionCount = 0,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'source_file': sourceFile,
        'question_count': questionCount,
        'is_default': isDefault ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory QuestionBank.fromMap(Map<String, dynamic> map) => QuestionBank(
        id: map['id'] as String,
        name: map['name'] as String,
        sourceFile: map['source_file'] as String?,
        questionCount: map['question_count'] as int? ?? 0,
        isDefault: (map['is_default'] as int?) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}

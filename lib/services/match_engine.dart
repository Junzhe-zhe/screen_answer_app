import 'dart:math';
import '../models/match_result.dart';
import '../utils/text_preprocessor.dart';

class MatchEngine {
  final List<QuestionPair> _pairs;
  final Map<String, QuestionPair> _exactMap;

  MatchEngine(this._pairs)
      : _exactMap = {
          for (final p in _pairs) TextPreprocessor.preprocess(p.question): p
        };

  /// 三级匹配流水线
  MatchResult match(String ocrText, {String ocrType = ''}) {
    final preprocessed = TextPreprocessor.preprocess(ocrText);
    if (preprocessed.isEmpty) {
      // 预处理后为空，尝试用原始文本（仅做基本清理）再匹配
      final raw = TextPreprocessor.preprocessRaw(ocrText);
      if (raw.isEmpty) return MatchResult.empty();
      return _fuzzyResult(_scorePairs(raw, ocrType: ocrType));
    }

    return _exactAndContainMatch(preprocessed, ocrType: ocrType) ??
        _fuzzyResult(_scorePairs(preprocessed, ocrType: ocrType));
  }

  /// 带候选列表的匹配：正常匹配 + 失败时返回 Top-3 候选
  /// 与 match() 共享 L1/L1.5/模糊评分逻辑
  MatchResult matchWithCandidates(String ocrText, {String ocrType = ''}) {
    final preprocessed = TextPreprocessor.preprocess(ocrText);
    if (preprocessed.isEmpty) {
      final raw = TextPreprocessor.preprocessRaw(ocrText);
      if (raw.isEmpty) return MatchResult.empty();
      return _fuzzyWithCandidates(_scorePairs(raw, ocrType: ocrType));
    }

    return _exactAndContainMatch(preprocessed, ocrType: ocrType) ??
        _fuzzyWithCandidates(_scorePairs(preprocessed, ocrType: ocrType));
  }

  /// L1: 精确匹配 (O(1)) + L1.5: 包含匹配，未命中返回 null
  MatchResult? _exactAndContainMatch(String preprocessed,
      {String ocrType = ''}) {
    // L1: 精确匹配。按题型从原始题目列表筛选，避免 exactMap 中的同题覆盖或错题型命中。
    for (final pair in _pairs.reversed) {
      if (!_isTypeCompatible(pair, ocrType, allowUnknownOcrType: true)) continue;
      if (TextPreprocessor.preprocess(pair.question) != preprocessed) continue;
      return MatchResult(
        answer: pair.answer,
        matchedQuestion: pair.question,
        confidence: 1.0,
        level: MatchLevel.exact,
        explanation: pair.explanation,
      );
    }

    // L1.5: 包含匹配 - OCR 文本包含整道题目（OCR 常带题号、选项等噪声）
    var bestContainScore = 0.0;
    QuestionPair? bestContainPair;
    for (final entry in _exactMap.entries) {
      final bankQ = entry.key;
      final pair = entry.value;
      if (!_isTypeCompatible(pair, ocrType, allowUnknownOcrType: true)) continue;
      if (bankQ.length < 8) continue; // 太短的题目跳过包含匹配
      if (preprocessed.contains(bankQ)) {
        // OCR 包含完整题目 -> 精确匹配
        return MatchResult(
          answer: pair.answer,
          matchedQuestion: pair.question,
          confidence: 0.98,
          level: MatchLevel.exact,
          explanation: pair.explanation,
        );
      }
      // 题目包含 OCR 核心内容（OCR 只截到了部分题目）
      // 阈值降低：OCR 现在只提取题干（不含选项），短至5字符也可匹配
      if (bankQ.contains(preprocessed) && preprocessed.length >= 5) {
        final score = preprocessed.length / bankQ.length;
        if (score > bestContainScore) {
          bestContainScore = score;
          bestContainPair = pair;
        }
      }
      // 部分包含：OCR 与题库题目有足够长的公共子串
      if (!preprocessed.contains(bankQ) && !bankQ.contains(preprocessed)) {
        final overlap = _longestCommonSubstring(preprocessed, bankQ);
        if (overlap.length >= 8 && overlap.length >= bankQ.length * 0.5) {
          final score = overlap.length / bankQ.length;
          if (score > bestContainScore) {
            bestContainScore = score;
            bestContainPair = pair;
          }
        }
      }
    }
    if (bestContainPair != null && bestContainScore >= 0.4) {
      return MatchResult(
        answer: bestContainPair.answer,
        matchedQuestion: bestContainPair.question,
        confidence: bestContainScore,
        level: MatchLevel.exact,
        explanation: bestContainPair.explanation,
      );
    }
    return null;
  }

  /// L2: 对全部题目做模糊评分（一次遍历，同时收集候选）
  _FuzzyOutcome _scorePairs(String preprocessed, {String ocrType = ''}) {
    var bestScore = 0.0;
    QuestionPair? bestPair;
    final scored = <_ScoredPair>[];

    for (final pair in _pairs) {
      if (!_isTypeCompatible(
        pair,
        ocrType,
        allowUnknownOcrType: ocrType.isEmpty,
      )) {
        continue;
      }
      final target = TextPreprocessor.preprocess(pair.question);
      final score = _partialRatio(preprocessed, target);
      if (score > bestScore) {
        bestScore = score;
        bestPair = pair;
      }
      if (score > 0) {
        scored.add(_ScoredPair(pair, score));
      }
      if (bestScore >= 0.95) break;
    }
    return _FuzzyOutcome(bestPair, bestScore, scored);
  }

  /// 模糊评分 -> 普通匹配结果（无候选列表）
  MatchResult _fuzzyResult(_FuzzyOutcome outcome) {
    final bestPair = outcome.bestPair;
    if (bestPair != null && outcome.bestScore >= 0.7) {
      return MatchResult(
        answer: bestPair.answer,
        matchedQuestion: bestPair.question,
        confidence: outcome.bestScore,
        level: MatchLevel.fuzzy,
        explanation: bestPair.explanation,
      );
    }
    return MatchResult.empty();
  }

  /// 模糊评分 -> 带候选列表的匹配结果
  MatchResult _fuzzyWithCandidates(_FuzzyOutcome outcome) {
    final bestPair = outcome.bestPair;
    if (bestPair != null && outcome.bestScore >= 0.7) {
      return MatchResult(
        answer: bestPair.answer,
        matchedQuestion: bestPair.question,
        confidence: outcome.bestScore,
        level: MatchLevel.fuzzy,
        explanation: bestPair.explanation,
      );
    }

    // 匹配失败，返回 Top-3 候选
    final scored = outcome.scored..sort((a, b) => b.score.compareTo(a.score));
    final topN = scored.take(3).toList();

    if (topN.isEmpty) return MatchResult.empty();

    return MatchResult(
      answer: '',
      matchedQuestion: '',
      confidence: 0.0,
      level: MatchLevel.none,
      candidates: topN
          .map((s) => CandidateItem(
                question: s.pair.question,
                answer: s.pair.answer,
                explanation: s.pair.explanation,
                score: s.score,
              ))
          .toList(),
    );
  }

  bool _isTypeCompatible(
    QuestionPair pair,
    String ocrType, {
    required bool allowUnknownOcrType,
  }) {
    if (ocrType.isEmpty) {
      // 未识别题型时允许精确/包含匹配保留兼容性；模糊评分由调用方禁止跨题型。
      return allowUnknownOcrType || pair.type.isNotEmpty;
    }
    return pair.type == ocrType;
  }

  /// 最长公共子串
  static String _longestCommonSubstring(String a, String b) {
    if (a.isEmpty || b.isEmpty) return '';
    final m = a.length, n = b.length;
    var maxLen = 0, endIdx = 0;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
          if (dp[i][j] > maxLen) {
            maxLen = dp[i][j];
            endIdx = i;
          }
        }
      }
    }
    return a.substring(endIdx - maxLen, endIdx);
  }

  /// partial_ratio: 较短文本在较长文本中的滑动窗口最佳匹配
  static double _partialRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final short = a.length < b.length ? a : b;
    final long = a.length < b.length ? b : a;

    // 如果短文本长度 <= 5，用 Levenshtein distance ratio
    if (short.length <= 5) {
      final d = _levenshtein(
          short, long.substring(0, min(short.length, long.length)));
      final maxLen = max(short.length, long.length);
      return maxLen == 0 ? 0.0 : 1.0 - (d / maxLen);
    }

    double bestScore = 0.0;
    for (var i = 0; i <= long.length - short.length; i++) {
      final window = long.substring(i, i + short.length);
      final d = _levenshtein(short, window);
      final score = 1.0 - (d / short.length);
      if (score > bestScore) {
        bestScore = score;
        if (bestScore >= 0.95) break;
      }
    }
    return bestScore;
  }

  /// Levenshtein 编辑距离
  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    var prev = List<int>.generate(s2.length + 1, (i) => i);
    var curr = List<int>.filled(s2.length + 1, 0);

    for (var i = 1; i <= s1.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        curr[j] = min(prev[j] + 1, min(curr[j - 1] + 1, prev[j - 1] + cost));
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[s2.length];
  }
}

class QuestionPair {
  final String question;
  final String answer;
  final String? explanation;
  final String type; // 'single' | 'multi' | 'judge' | ''

  QuestionPair({
    required this.question,
    required this.answer,
    this.explanation,
    String? type,
  }) : type = type ?? QuestionPair.inferType(answer);

  /// 从答案推断题型，兼容导入题库中的"字母 + 选项内容"格式。
  static String inferType(String answer) {
    final value = answer.trim().toUpperCase();
    if (value.isEmpty) return '';

    final judgeText = value.replaceAll(RegExp(r'[\s.、．:：()（）]'), '');
    final judgeWords = RegExp(r'(正确|错误|对|错|是|否|TRUE|FALSE)')
        .allMatches(judgeText)
        .length;
    if (RegExp(r'^(正确|错误|对|错|是|否|TRUE|FALSE|T|F)$').hasMatch(judgeText) ||
        judgeWords >= 2 ||
        (RegExp(r'^[A-H](正确|错误|对|错|是|否)$').hasMatch(judgeText))) {
      return 'judge';
    }

    final markers = RegExp(r'(?<![A-Z])[A-H](?=\s*[.、．:：)]|$)')
        .allMatches(value)
        .map((m) => m.group(0)!.trim())
        .where((m) => m.isNotEmpty)
        .toSet();
    if (markers.length >= 2) return 'multi';
    if (markers.length == 1 &&
        RegExp(r'^\s*[A-H]\s*(?:[.、．:：)].*)?$', caseSensitive: false)
            .hasMatch(value)) {
      return 'single';
    }

    if (RegExp(r'^[A-H]{2,}$').hasMatch(value.replaceAll(RegExp(r'[\s,，、;；/]'), ''))) {
      return 'multi';
    }
    if (RegExp(r'^[A-H]$').hasMatch(value)) return 'single';
    return '';
  }
}

/// 内部辅助：带分数的题目对
class _ScoredPair {
  final QuestionPair pair;
  final double score;
  _ScoredPair(this.pair, this.score);
}

/// 内部辅助：模糊评分遍历结果
class _FuzzyOutcome {
  final QuestionPair? bestPair;
  final double bestScore;
  final List<_ScoredPair> scored;
  _FuzzyOutcome(this.bestPair, this.bestScore, this.scored);
}

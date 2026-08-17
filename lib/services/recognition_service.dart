import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/match_result.dart';
import '../models/question.dart';
import '../models/question_bank.dart';
import '../services/database_service.dart';
import 'diagnostic_log_service.dart';
import '../services/match_engine.dart';
import '../utils/constants.dart';

const _uuid = Uuid();

/// 全局识别服务：在应用启动时即注册 MethodChannel 处理器，
/// 保证独立运行的 FloatService 发回的 OCR 文本能被立刻匹配并返回结果。
/// 即使首页尚未加载，悬浮窗也能正常工作。
class RecognitionService {
  static final MethodChannel _channel =
      const MethodChannel(AppConstants.recognitionChannel);

  static MatchEngine? _matchEngine;
  static QuestionBank? _activeBank; // 兼容旧引用：当前命中的题库
  static bool _isInitialized = false;
  static Completer<void> _initCompleter = Completer<void>();

  /// 初始化并注册原生通道处理器
  static Future<void> initialize() async {
    if (_isInitialized) return _initCompleter.future;
    _isInitialized = true;

    _channel.setMethodCallHandler(_onMethodCall);
    await _loadDefaultBank();
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  /// 仅用于单元测试：重置全局状态，使下一次 initialize() 重新执行完整初始化。
  @visibleForTesting
  static void resetForTest() {
    _matchEngine = null;
    _activeBank = null;
    _isInitialized = false;
    _initCompleter = Completer<void>();
  }

  /// 等待初始化完成（供需要确保引擎准备好的调用方使用）
  static Future<void> get ready => _initCompleter.future;

  /// 获取当前题库
  static QuestionBank? get activeBank => _activeBank;

  /// 重新加载默认题库
  static Future<void> reloadBank() async => _loadDefaultBank();

  /// 加载指定题库（供首页切换后立即同步到悬浮窗匹配引擎）
  static Future<void> loadBank(String bankId) async {
    try {
      final bank = await DatabaseService.getBank(bankId);
      if (bank != null) await _applyBank(bank);
    } catch (e, stack) {
      debugPrint('[RecognitionService] loadBank error: $e');
      unawaited(DiagnosticLogService.write('recognition-load-bank', e, stack));
    }
  }

  static Future<void> _loadDefaultBank() async {
    try {
      // 多题库：加载全部题库的题目，合并构建单个匹配引擎。
      // 实际使用时用户可能在不同题库间切换做题，全部加载可保证
      // 悬浮窗在任何题库界面都能命中。
      final banks = await DatabaseService.getBanks();
      if (banks.isEmpty) {
        _matchEngine = null;
        _activeBank = null;
        return;
      }
      final allPairs = <QuestionPair>[];
      for (final bank in banks) {
        final pairs = await DatabaseService.getQuestionPairs(bank.id);
        for (final p in pairs) {
          allPairs.add(QuestionPair(
            question: p.question,
            answer: p.answer,
            explanation: p.explanation,
            type: p.type,
            bankId: bank.id,
          ));
        }
      }
      _matchEngine = MatchEngine(allPairs);
      _activeBank = banks.firstWhere(
        (b) => b.isDefault,
        orElse: () => banks.first,
      );
      debugPrint('[RecognitionService] loaded ${banks.length} banks, '
          '${allPairs.length} questions total (multi-bank matching)');
    } catch (e, stack) {
      debugPrint('[RecognitionService] load bank error: $e');
      unawaited(DiagnosticLogService.write('recognition-load-default-bank', e, stack));
    }
  }

  static Future<void> _applyBank(QuestionBank bank) async {
    // 兼容旧调用：加载单个题库时也保留其他题库（重新全量加载）
    await _loadDefaultBank();
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    try {
      if (call.method == 'recognize') {
      String text;
      String ocrType = '';
      int? generation;
      if (call.arguments is Map) {
        final args = call.arguments as Map;
        text = args['text'] as String? ?? '';
        ocrType = args['type'] as String? ?? '';
        generation = (args['generation'] as num?)?.toInt();
      } else {
        // 向后兼容：旧版本传递纯字符串
        text = call.arguments as String;
      }
        await _process(text, ocrType: ocrType, generation: generation);
        return null;
      }
      return null;
    } catch (error, stack) {
      unawaited(DiagnosticLogService.write('recognition-method-call', error, stack));
      return null;
    }
  }

  static Future<void> _process(
    String ocrText, {
    String ocrType = '',
    int? generation,
  }) async {
    // 等待初始化完成，但加超时保护，避免初始化卡住导致原生端识别超时
    try {
      await ready.timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint('[RecognitionService] init wait timeout, continue with current engine');
    }

    if (_matchEngine == null || _activeBank == null) {
      await _sendResult(
        text: ocrText,
        answer: '',
        explanation: '',
        level: 'none',
        candidates: const [],
        generation: generation,
      );
      return;
    }

    final result = _matchEngine!.matchWithCandidates(ocrText, ocrType: ocrType);
    final candSummary = result.candidates
        .map((c) => '[score=${c.score.toStringAsFixed(2)} q=${c.question.length > 40 ? c.question.substring(0, 40) : c.question}]')
        .join(' | ');
    debugPrint('[RecognitionService] match: in=[$ocrText] level=${result.level.name} '
        'answer=[${result.answer}] matched=[${result.matchedQuestion}] '
        'candidates=${result.candidates.length} $candSummary');
    unawaited(DiagnosticLogService.write('recognition-match', Exception(
      'in=[$ocrText] level=${result.level.name} answer=[${result.answer}] '
      'matched=[${result.matchedQuestion}] candidates=${result.candidates.length} $candSummary')));

    // 历史记录异步写入，不阻塞识别结果回传（长会话上百次识别时保证响应速度）
    unawaited(() async {
      try {
        await DatabaseService.saveHistory(RecognitionHistory(
          id: _uuid.v4(),
          ocrText: ocrText,
          matchedQuestion: result.matchedQuestion,
          matchedAnswer: result.answer,
          confidence: result.confidence,
          matchLevel: result.level.name,
          bankId: result.matchedBankId ?? _activeBank!.id,
          timestamp: DateTime.now(),
        ));
        // 控制历史记录总量，避免长时间使用后数据库无限膨胀
        await DatabaseService.trimHistory(500);
      } catch (e) {
        debugPrint('[RecognitionService] saveHistory error: $e');
      }
    }());

    await _sendResult(
      text: result.matchedQuestion.isNotEmpty ? result.matchedQuestion : ocrText,
      answer: result.answer,
      explanation: result.explanation ?? '',
      level: result.level.name,
      candidates: result.candidates,
      generation: generation,
    );
  }

  static Future<void> _sendResult({
    required String text,
    required String answer,
    required String explanation,
    required String level,
    required List<CandidateItem> candidates,
    int? generation,
  }) async {
    try {
      await _channel.invokeMethod('result', {
        'text': text,
        'answer': answer,
        'explanation': explanation,
        'level': level,
        'candidates': candidates.map((c) => {
          'question': c.question,
          'answer': c.answer,
          'explanation': c.explanation ?? '',
          'score': c.score,
        }).toList(),
        'generation': generation,
      });
    } catch (e) {
      debugPrint('[RecognitionService] sendResult error: $e');
    }
  }
}

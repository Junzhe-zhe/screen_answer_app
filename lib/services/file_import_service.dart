import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../models/question.dart';
import '../utils/text_preprocessor.dart';

const _uuid = Uuid();

class QuestionItem {
  final String question;
  final String answer;
  final String? explanation;
  QuestionItem({required this.question, required this.answer, this.explanation});
}

class ParseResult {
  final List<QuestionItem> questions;
  final String? error;
  ParseResult(this.questions, [this.error]);
}

class FileImportService {
  static Future<ParseResult> importFile(
      Uint8List bytes, String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'json':
        return _parseJson(bytes);
      case 'csv':
        return _parseCsv(bytes);
      case 'xlsx':
        return _parseXlsx(bytes);
      default:
        return ParseResult([], '不支持的文件格式: .$ext');
    }
  }

  static ParseResult _parseJson(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      final list = jsonDecode(text) as List<dynamic>;
      final questions = <QuestionItem>[];
      for (final item in list) {
        final q = item['q'] ?? item['question'] ?? item['题目'] ?? item['问题'] ?? item['试题'] ?? '';
        final a = item['a'] ?? item['answer'] ?? item['答案'] ?? '';
        final e = item['e'] ?? item['explanation'] ?? item['解析'] ?? item['解析说明'];
        if (q is String && a is String && q.isNotEmpty && a.isNotEmpty) {
          questions.add(QuestionItem(
            question: q,
            answer: a,
            explanation: e is String && e.isNotEmpty ? e : null,
          ));
        }
      }
      return ParseResult(questions);
    } catch (e) {
      return ParseResult([], 'JSON 解析失败: $e');
    }
  }

  static ParseResult _parseCsv(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      // 统一换行符，支持 Windows (CRLF) 和 Unix (LF)
      final normalized = text.replaceAll('\r\n', '\n');
      final rows = const CsvToListConverter(eol: '\n').convert(normalized);
      if (rows.isEmpty) return ParseResult([], 'CSV 文件为空');
      final questions = <QuestionItem>[];
      final header = rows[0].map((c) => c.toString().toLowerCase()).toList();
      int? qIdx, aIdx;
      bool foundHeader = false;
      for (var i = 0; i < header.length; i++) {
        final h = header[i];
        if (h == 'question' || h == '题目' || h == '问题' || h == '试题') {
          qIdx = i;
          foundHeader = true;
        }
        if (h == 'answer' || h == '答案') {
          aIdx = i;
          foundHeader = true;
        }
      }
      if (qIdx == null && rows[0].isNotEmpty) qIdx = 0;
      if (aIdx == null && rows[0].length >= 2) aIdx = 1;
      if (qIdx == null || aIdx == null) return ParseResult([], '未找到题目/答案列');
      final startRow = foundHeader ? 1 : 0;
      for (var r = startRow; r < rows.length; r++) {
        final row = rows[r];
        if (row.length > qIdx && row.length > aIdx) {
          final q = row[qIdx].toString().trim();
          final a = row[aIdx].toString().trim();
          if (q.isNotEmpty && a.isNotEmpty) {
            questions.add(QuestionItem(question: q, answer: a));
          }
        }
      }
      return ParseResult(questions);
    } catch (e) {
      return ParseResult([], 'CSV 解析失败: $e');
    }
  }

  /// XLSX 解析 — 用 archive 解压 ZIP + 直接解析共享字符串 XML
  static ParseResult _parseXlsx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. 读取共享字符串表
      final sharedStrings = _readSharedStrings(archive);

      // 2. 读取 Sheet1 数据
      final sheetData = _readSheetData(archive, 'xl/worksheets/sheet1.xml');
      if (sheetData == null) return ParseResult([], '未找到 Sheet 数据');
      if (sheetData.rows.isEmpty) return ParseResult([], 'Sheet 为空');

      // 3. 检测国网模板
      final isGuowang = _detectGuowangTemplate(sheetData.rows, sharedStrings);

      // 4. 按对应格式解析
      if (isGuowang) {
        return _parseGuowangSheet(sheetData.rows, sharedStrings);
      } else {
        return _parseGenericSheet(sheetData.rows, sharedStrings);
      }
    } catch (e) {
      return ParseResult([], 'Excel 解析失败: $e');
    }
  }

  /// 读取共享字符串表
  static List<String> _readSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return [];
    final xml = utf8.decode(file.content as List<int>);
    final result = <String>[];
    final siRegex = RegExp(r'<si[^>]*>(.*?)</si>', dotAll: true);
    final tRegex = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
    for (final match in siRegex.allMatches(xml)) {
      final si = match.group(1) ?? '';
      final tMatch = tRegex.firstMatch(si);
      if (tMatch != null) {
        result.add(_xmlDecode(tMatch.group(1) ?? ''));
      }
    }
    return result;
  }

  /// 读取 Sheet 数据
  static _SheetData? _readSheetData(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    final xml = utf8.decode(file.content as List<int>);
    final rows = <_Row>[];
    final rowRegex = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true);
    final cellRegex = RegExp(
        r'(<c[^>]*r="([A-Z]+)(\d+)"[^>]*>(.*?)</c>)',
        dotAll: true);

    for (final rowMatch in rowRegex.allMatches(xml)) {
      final rowXml = rowMatch.group(1) ?? '';
      final cells = <int, String>{};
      for (final cellMatch in cellRegex.allMatches(rowXml)) {
        final fullCell = cellMatch.group(1) ?? '';
        final colLetter = cellMatch.group(2) ?? '';
        final colIdx = _colLetterToIndex(colLetter);
        cells[colIdx] = fullCell;
      }
      rows.add(_Row(cells));
    }
    return _SheetData(rows);
  }

  /// 检测是否为国网模板（找表头中是否包含"试题正文"）
  static bool _detectGuowangTemplate(
      List<_Row> rows, List<String> sharedStrings) {
    for (var r = 0; r < 5 && r < rows.length; r++) {
      for (final entry in rows[r].cells.entries) {
        final value = _cellValue(entry.value, sharedStrings);
        if (value.contains('试题正文')) return true;
      }
    }
    return false;
  }

  /// 解析国网学堂模板
  ///
  /// 支持两种布局：
  /// 1. 标准布局：选项合并到 oCol 单格用 $; 分隔，答案字母在 aCol
  /// 2. 分散列布局：选项分散在 oCol 及后续列，答案字母在更靠后的纯字母列
  ///    自动检测：首个数据行的 aCol 值若为纯字母 → 标准布局；否则 → 分散列布局
  static ParseResult _parseGuowangSheet(
      List<_Row> rows, List<String> sharedStrings) {
    // 找表头行
    int headerRow = -1;
    for (var r = 0; r < 5 && r < rows.length; r++) {
      for (final entry in rows[r].cells.entries) {
        if (_cellValue(entry.value, sharedStrings).contains('试题正文')) {
          headerRow = r;
          break;
        }
      }
      if (headerRow >= 0) break;
    }
    if (headerRow < 0) return ParseResult([], '未找到表头行');

    // 提取列映射
    int? qCol, oCol, aCol;
    for (final entry in rows[headerRow].cells.entries) {
      final v = _cellValue(entry.value, sharedStrings);
      if (v.contains('试题正文')) qCol = entry.key;
      if (v.contains('试题选项')) oCol = entry.key;
      if (v.contains('试题答案')) aCol = entry.key;
    }
    if (qCol == null || aCol == null) return ParseResult([], '缺少必需列');

    // 检测布局：首个数据行的 aCol 值若为纯字母 → 标准 $; 布局
    final firstDataRowIdx = headerRow + 1;
    final isStandardLayout = firstDataRowIdx < rows.length &&
        RegExp(r'^[A-Z]+$')
            .hasMatch(rows[firstDataRowIdx].cellValue(aCol, sharedStrings));

    final questions = <QuestionItem>[];

    if (isStandardLayout) {
      // === 标准布局：选项合并到 oCol 单格用 $; 分隔 ===
      for (var r = headerRow + 1; r < rows.length; r++) {
        final qText = rows[r].cellValue(qCol, sharedStrings);
        if (qText.isEmpty) continue;

        // 拆分选项
        final optionsRaw = oCol != null
            ? rows[r].cellValue(oCol, sharedStrings)
            : '';
        final options = <String>[];
        if (optionsRaw.isNotEmpty) {
          for (final part in optionsRaw.split('\$;')) {
            var opt = part.trim();
            if (opt.startsWith('\$')) opt = opt.substring(1).trim();
            if (opt.isNotEmpty) options.add(opt);
          }
        }

        final ansLetter = rows[r].cellValue(aCol, sharedStrings);
        questions.add(QuestionItem(
          question: _assembleQuestion(qText, options),
          answer: _assembleAnswer(ansLetter, options),
        ));
      }
    } else {
      // === 分散列布局：选项分散在 oCol 及后续列，答案在纯字母列 ===
      for (var r = headerRow + 1; r < rows.length; r++) {
        final qText = rows[r].cellValue(qCol, sharedStrings);
        if (qText.isEmpty) continue;

        // 从 oCol 起按列序扫描，收集连续非空值作为选项，遇到纯字母格即答案
        final options = <String>[];
        String ansLetter = '';
        final sortedCols = rows[r].cells.keys.toList()..sort();
        bool collecting = false;
        for (final col in sortedCols) {
          if (oCol != null && col == oCol) {
            collecting = true;
          }
          if (!collecting) continue;

          final val = rows[r].cellValue(col, sharedStrings);
          if (val.isEmpty) continue;

          // 纯字母格（如 "A"、"ABD"）→ 答案
          if (RegExp(r'^[A-Z]+$').hasMatch(val)) {
            ansLetter = val;
            break;
          }

          options.add(val);
        }

        questions.add(QuestionItem(
          question: _assembleQuestion(qText, options),
          answer: _assembleAnswer(ansLetter, options),
        ));
      }
    }

    return ParseResult(questions);
  }

  /// 组装题目文本：题干 + A. 选项 逐行拼接
  static String _assembleQuestion(String qText, List<String> options) {
    const labels = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final buffer = StringBuffer(qText);
    if (options.isNotEmpty) {
      buffer.write('\n');
      for (var i = 0; i < options.length && i < labels.length; i++) {
        buffer.write('${labels[i]}. ${options[i]}');
        if (i < options.length - 1) buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// 组装答案文本：字母 + 对应选项内容，多选用"；"连接
  static String _assembleAnswer(String ansLetter, List<String> options) {
    const labels = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final answerParts = <String>[];
    if (options.isNotEmpty && ansLetter.isNotEmpty) {
      for (var i = 0; i < ansLetter.length; i++) {
        final idx = labels.indexOf(ansLetter[i].toUpperCase());
        if (idx >= 0 && idx < options.length) {
          answerParts.add('${ansLetter[i]}. ${options[idx]}');
        }
      }
    }
    return answerParts.isNotEmpty ? answerParts.join('；') : ansLetter;
  }

  /// 通用 Excel 解析
  static ParseResult _parseGenericSheet(
      List<_Row> rows, List<String> sharedStrings) {
    if (rows.length < 2) return ParseResult([], '文件内容不足');
    final questions = <QuestionItem>[];

    // 检测表头
    int? qCol, aCol;
    final headerCells = rows[0];
    for (final entry in headerCells.cells.entries) {
      final v = _cellValue(entry.value, sharedStrings).toLowerCase();
      if (v == 'question' || v == '题目' || v == '问题' || v == '试题') {
        qCol = entry.key;
      }
      if (v == 'answer' || v == '答案') {
        aCol = entry.key;
      }
    }
    // 未检测到表头则默认第0列=题目，第1列=答案，从第1行开始
    qCol ??= 0;
    aCol ??= 1;
    const startRow = 1;

    for (var r = startRow; r < rows.length; r++) {
      final q = rows[r].cellValue(qCol, sharedStrings);
      final a = rows[r].cellValue(aCol, sharedStrings);
      if (q.isNotEmpty && a.isNotEmpty) {
        questions.add(QuestionItem(question: q, answer: a));
      }
    }
    return ParseResult(questions);
  }

  /// 从 cell XML 内容中提取值
  static String _cellValue(String cellXml, List<String> sharedStrings) {
    // 检查 cell 类型属性
    final typeMatch = RegExp(r'<c[^>]*\st="(\w+)"').firstMatch(cellXml);
    final cellType = typeMatch?.group(1);

    // 共享字符串类型 (t="s")
    if (cellType == 's') {
      final vMatch = RegExp(r'<v>(\d+)</v>').firstMatch(cellXml);
      if (vMatch != null) {
        final idx = int.tryParse(vMatch.group(1) ?? '') ?? -1;
        if (idx >= 0 && idx < sharedStrings.length) {
          return sharedStrings[idx].trim();
        }
      }
      return '';
    }

    // inline string (t="inlineStr")
    if (cellType == 'inlineStr') {
      final inlineMatch =
          RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).firstMatch(cellXml);
      if (inlineMatch != null) {
        return _xmlDecode(inlineMatch.group(1) ?? '').trim();
      }
      return '';
    }

    // 纯数值 (无 t 属性 或 t="n")
    final vMatch = RegExp(r'<v>([^<]+)</v>').firstMatch(cellXml);
    if (vMatch != null) {
      return vMatch.group(1)?.trim() ?? '';
    }

    // 兜底：尝试任何 <t> 标签
    final inlineMatch =
        RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).firstMatch(cellXml);
    if (inlineMatch != null) {
      return _xmlDecode(inlineMatch.group(1) ?? '').trim();
    }

    return '';
  }

  /// XML 实体解码
  static String _xmlDecode(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }

  /// 列字母 → 数字索引
  static int _colLetterToIndex(String letters) {
    var result = 0;
    for (var i = 0; i < letters.length; i++) {
      result = result * 26 + (letters.codeUnitAt(i) - 'A'.codeUnitAt(0) + 1);
    }
    return result - 1;
  }

  static List<Question> toDbQuestions(
      List<QuestionItem> items, String bankId) {
    final now = DateTime.now();
    return items
        .map((item) => Question(
              id: _uuid.v4(),
              bankId: bankId,
              rawText: item.question,
              preprocessedText: TextPreprocessor.preprocess(item.question),
              answer: item.answer,
              explanation: item.explanation,
              createdAt: now,
            ))
        .toList();
  }
}

// -------- 内部数据结构 --------

class _SheetData {
  final List<_Row> rows;
  _SheetData(this.rows);
}

class _Row {
  /// column index → cell XML content
  final Map<int, String> cells;
  _Row(this.cells);

  String cellValue(int colIdx, List<String> sharedStrings) {
    final cellXml = cells[colIdx];
    if (cellXml == null) return '';
    return FileImportService._cellValue(cellXml, sharedStrings);
  }
}

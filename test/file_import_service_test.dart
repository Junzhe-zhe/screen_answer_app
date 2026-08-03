/// 文件导入解析单元测试
///
/// 覆盖场景:
/// - JSON 格式导入（标准格式、带 explanation 字段、字段名兼容）
/// - CSV 格式导入（标准格式、中文列名、列名自动检测）
/// - XLSX 格式导入（通用格式、国网学堂模板）
/// - 错误处理（格式不支持、文件损坏、空文件）
/// - QuestionItem → Question 转换
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_answer_app/services/file_import_service.dart';

void main() {
  // ==================== 辅助函数 ====================

  Uint8List toBytes(String text) => Uint8List.fromList(utf8.encode(text));

  // ==================== JSON 导入测试 ====================

  group('FileImportService - JSON 导入', () {
    test('标准 JSON 格式 - 使用 q/a 字段名', () async {
      final json = jsonEncode([
        {'q': '第一题内容', 'a': '答案一'},
        {'q': '第二题内容', 'a': '答案二'},
        {'q': '第三题内容', 'a': '答案三'},
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'questions.json');
      expect(result.error, isNull);
      expect(result.questions.length, 3);
      expect(result.questions[0].question, '第一题内容');
      expect(result.questions[0].answer, '答案一');
    });

    test('兼容 question/answer 字段名', () async {
      final json = jsonEncode([
        {'question': '测试题目', 'answer': '测试答案'},
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'test.json');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question, '测试题目');
    });

    test('空题目或空答案应被跳过', () async {
      final json = jsonEncode([
        {'q': '有效题目', 'a': '有效答案'},
        {'q': '', 'a': '空题目'},
        {'q': '空答案', 'a': ''},
        {'q': '', 'a': ''},
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'test.json');
      expect(result.error, isNull);
      expect(result.questions.length, 1); // 只有第一个有效
    });

    test('空 JSON 数组', () async {
      final result = await FileImportService.importFile(toBytes('[]'), 'empty.json');
      expect(result.error, isNull);
      expect(result.questions, isEmpty);
    });

    test('无效 JSON 应返回错误', () async {
      final result = await FileImportService.importFile(toBytes('{invalid json}'), 'bad.json');
      expect(result.error, isNotNull);
      expect(result.error, contains('JSON 解析失败'));
    });

    test('非数组 JSON 应返回错误', () async {
      final result = await FileImportService.importFile(toBytes('{"key": "value"}'), 'obj.json');
      expect(result.error, isNotNull);
    });

    test('JSON 含 explanation 字段应被正确解析', () async {
      final json = jsonEncode([
        {
          'q': '带解析的题目',
          'a': '答案',
          'explanation': '详细解题步骤...',
        },
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'with_explanation.json');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].explanation, '详细解题步骤...');
    });

    test('JSON 解析 - 中文解析字段名', () async {
      final json = jsonEncode([
        {
          'q': '带解析的题目',
          'a': '答案',
          '解析': '中文解析字段',
        },
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'with_explanation.json');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].explanation, '中文解析字段');
    });

    test('JSON 解析 - 空 explanation 应为 null', () async {
      final json = jsonEncode([
        {
          'q': '无解析题目',
          'a': '答案',
          'explanation': '',
        },
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'empty_explanation.json');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].explanation, isNull);
    });

    test('JSON 解析 - 解析说明字段名', () async {
      final json = jsonEncode([
        {'q': '带解析的题目', 'a': '答案', '解析说明': '说明文字'},
      ]);
      final result = await FileImportService.importFile(toBytes(json), 'shuoming.json');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].explanation, '说明文字');
    });

    test('大 JSON 文件导入', () async {
      final items = List.generate(1000, (i) => {
        'q': '第${i + 1}题：测试题目内容',
        'a': '答案$i',
      });
      final json = jsonEncode(items);
      final stopwatch = Stopwatch()..start();
      final result = await FileImportService.importFile(toBytes(json), 'large.json');
      stopwatch.stop();
      expect(result.error, isNull);
      expect(result.questions.length, 1000);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

  // ==================== CSV 导入测试 ====================

  group('FileImportService - CSV 导入', () {
    test('标准 CSV 格式 - 英文列名', () async {
      final csv = 'question,answer\n'
          '第一题,答案一\n'
          '第二题,答案二\n';
      final result = await FileImportService.importFile(toBytes(csv), 'questions.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 2);
      expect(result.questions[0].question, '第一题');
      expect(result.questions[0].answer, '答案一');
    });

    test('中文列名 - 题目/答案', () async {
      final csv = '题目,答案\n'
          '测试题目,测试答案\n';
      final result = await FileImportService.importFile(toBytes(csv), 'test.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
    });

    test('无表头 CSV - 默认使用第1、2列', () async {
      final csv = '第一题,答案一\n'
          '第二题,答案二\n';
      final result = await FileImportService.importFile(toBytes(csv), 'no_header.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 2);
    });

    test('空行应被跳过', () async {
      final csv = 'question,answer\n'
          '第一题,答案一\n'
          ',\n'
          '第二题,答案二\n'
          ',\n';
      final result = await FileImportService.importFile(toBytes(csv), 'test.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 2);
    });

    test('空 CSV 文件', () async {
      final result = await FileImportService.importFile(toBytes(''), 'empty.csv');
      expect(result.error, isNotNull);
    });

    test('Windows CRLF 换行符', () async {
      final csv = 'question,answer\r\n第一题,答案一\r\n第二题,答案二\r\n';
      final result = await FileImportService.importFile(toBytes(csv), 'crlf.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 2);
      expect(result.questions[0].answer, '答案一');
    });

    test('CSV 含 BOM 头', () async {
      // UTF-8 BOM: \xEF\xBB\xBF
      final bom = '\uFEFF';
      final csv = '${bom}question,answer\n'
          '第一题,答案一\n';
      final result = await FileImportService.importFile(toBytes(csv), 'bom.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
    });

    test('CSV 含引号包裹的字段', () async {
      final csv = 'question,answer\n'
          '"包含,逗号的题目","包含,逗号的答案"\n';
      final result = await FileImportService.importFile(toBytes(csv), 'quoted.csv');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question, '包含,逗号的题目');
    });
  });

  // ==================== XLSX 导入测试 ====================

  group('FileImportService - XLSX 导入', () {
    /// XML 转义（与 _xmlDecode 相反）
    String xmlEscape(String s) {
      return s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;')
          .replaceAll("'", '&apos;');
    }

    /// 构造最小有效 XLSX 字节数据（ZIP 格式包含 XML）
    ///
    /// [rows] 格式: 每行是一个 Map<列字母, 字符串值>
    /// 共享字符串会自动收集并写入 xl/sharedStrings.xml
    /// 单元格引用使用共享字符串索引（s 类型）
    Uint8List createXlsx(List<Map<String, String>> rows) {
      // 收集所有唯一字符串 → 共享字符串表
      final sharedStrings = <String>[];
      final strIndex = <String, int>{};
      int getIndex(String s) {
        final idx = strIndex[s];
        if (idx != null) return idx;
        final newIdx = sharedStrings.length;
        sharedStrings.add(s);
        strIndex[s] = newIdx;
        return newIdx;
      }

      // 预注册所有字符串
      for (final row in rows) {
        for (final v in row.values) {
          getIndex(v);
        }
      }

      // 构建 sheet1.xml — 使用共享字符串引用
      final sheetBuf = StringBuffer();
      sheetBuf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      sheetBuf.writeln(
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
      sheetBuf.writeln('<sheetData>');
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        sheetBuf.writeln('<row r="${r + 1}">');
        for (final entry in row.entries) {
          final colLetter = entry.key;
          final value = entry.value;
          final idx = getIndex(value);
          sheetBuf.writeln(
              '<c r="$colLetter${r + 1}" t="s"><v>$idx</v></c>');
        }
        sheetBuf.writeln('</row>');
      }
      sheetBuf.writeln('</sheetData>');
      sheetBuf.writeln('</worksheet>');

      // 构建 sharedStrings.xml
      final ssBuf = StringBuffer();
      ssBuf.writeln(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      ssBuf.writeln(
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${sharedStrings.length}" uniqueCount="${sharedStrings.length}">');
      for (final s in sharedStrings) {
        ssBuf.writeln('<si><t>${xmlEscape(s)}</t></si>');
      }
      ssBuf.writeln('</sst>');

      // 构建 [Content_Types].xml
      final ctBuf = StringBuffer();
      ctBuf.writeln(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      ctBuf.writeln(
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">');
      ctBuf.writeln(
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>');
      ctBuf.writeln(
          '<Default Extension="xml" ContentType="application/xml"/>');
      ctBuf.writeln(
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
      ctBuf.writeln(
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      ctBuf.writeln(
          '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>');
      ctBuf.writeln('</Types>');

      // 构建 _rels/.rels
      final relsBuf = StringBuffer();
      relsBuf.writeln(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      relsBuf.writeln(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
      relsBuf.writeln(
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>');
      relsBuf.writeln('</Relationships>');

      // 构建 xl/workbook.xml
      final wbBuf = StringBuffer();
      wbBuf.writeln(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      wbBuf.writeln(
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
      wbBuf.writeln('<sheets>');
      wbBuf.writeln(
          '<sheet name="Sheet1" sheetId="1" r:id="rId1"/>');
      wbBuf.writeln('</sheets>');
      wbBuf.writeln('</workbook>');

      // 构建 xl/_rels/workbook.xml.rels
      final wbRelsBuf = StringBuffer();
      wbRelsBuf.writeln(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
      wbRelsBuf.writeln(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
      wbRelsBuf.writeln(
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>');
      wbRelsBuf.writeln(
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>');
      wbRelsBuf.writeln('</Relationships>');

      // 用 archive 包构建 ZIP
      final archive = Archive();
      archive.addFile(ArchiveFile(
          '[Content_Types].xml', ctBuf.length, utf8.encode(ctBuf.toString())));
      archive.addFile(ArchiveFile(
          '_rels/.rels', relsBuf.length, utf8.encode(relsBuf.toString())));
      archive.addFile(ArchiveFile('xl/workbook.xml', wbBuf.length,
          utf8.encode(wbBuf.toString())));
      archive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels',
          wbRelsBuf.length, utf8.encode(wbRelsBuf.toString())));
      archive.addFile(ArchiveFile('xl/worksheets/sheet1.xml',
          sheetBuf.length, utf8.encode(sheetBuf.toString())));
      archive.addFile(ArchiveFile('xl/sharedStrings.xml', ssBuf.length,
          utf8.encode(ssBuf.toString())));

      final zipBytes = ZipEncoder().encode(archive);
      return Uint8List.fromList(zipBytes ?? []);
    }

    test('非 XLSX 文件应返回错误', () async {
      final result = await FileImportService.importFile(
        toBytes('not a zip file'),
        'test.xlsx',
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('Excel 解析失败'));
    });

    test('不支持的文件格式', () async {
      final result = await FileImportService.importFile(
        toBytes('some data'),
        'test.txt',
      );
      expect(result.error, isNotNull);
      expect(result.error, contains('不支持的文件格式'));
    });

    test('通用 XLSX - 解析第一、二列', () async {
      final xlsx = createXlsx([
        {'A': '题目', 'B': '答案'},
        {'A': '第一题内容', 'B': '答案一'},
        {'A': '第二题内容', 'B': '答案二'},
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 2);
      expect(result.questions[0].question, '第一题内容');
      expect(result.questions[0].answer, '答案一');
      expect(result.questions[1].question, '第二题内容');
      expect(result.questions[1].answer, '答案二');
    });

    test('通用 XLSX - 跳过空行', () async {
      final xlsx = createXlsx([
        {'A': '题目', 'B': '答案'},
        {'A': '有效题目', 'B': '有效答案'},
        {'A': '', 'B': ''},
        {'A': '第三题', 'B': '答案三'},
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 2);
    });

    test('国网模板检测 - 表头含「试题正文」应被识别', () async {
      final xlsx = createXlsx([
        {'A': '试题正文', 'B': '试题选项', 'C': '试题答案'},
        {'A': '测试题目', 'B': 'A. 选项一\$;B. 选项二', 'C': 'A'},
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      // 国网路径应正确解析
      expect(result.questions.length, 1);
      expect(result.questions[0].question, contains('测试题目'));
      expect(result.questions[0].question, contains('A. A. 选项一'));
      expect(result.questions[0].question, contains('B. B. 选项二'));
      expect(result.questions[0].answer, 'A. A. 选项一');
    });

    test('国网模板解析 - 题目+选项+答案解析', () async {
      final xlsx = createXlsx([
        {'A': '试题正文', 'B': '试题选项', 'C': '试题答案', 'D': '试题解析'},
        {
          'A': '以下哪个是 Flutter 的编程语言？',
          'B': 'A. Java\$;B. Dart\$;C. Python\$;D. C++',
          'C': 'B',
          'D': 'Flutter 使用 Dart 语言开发'
        },
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question,
          contains('以下哪个是 Flutter 的编程语言？'));
      expect(result.questions[0].question, contains('A. A. Java'));
      expect(result.questions[0].question, contains('B. B. Dart'));
      expect(result.questions[0].question, contains('C. C. Python'));
      expect(result.questions[0].question, contains('D. D. C++'));
      expect(result.questions[0].answer, 'B. B. Dart');
    });

    test('国网模板 - 多选答案应解析为选项文本', () async {
      final xlsx = createXlsx([
        {'A': '试题正文', 'B': '试题选项', 'C': '试题答案'},
        {
          'A': '以下哪些是编程语言？',
          'B': 'A. Python\$;B. Flutter\$;C. Java\$;D. Dart',
          'C': 'AC',
        },
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      // 多选答案 "AC" → "A. A. Python；C. C. Java"
      expect(result.questions[0].answer, 'A. A. Python；C. C. Java');
    });

    test('国网模板 - 答案字母超出选项范围时回退为字母', () async {
      final xlsx = createXlsx([
        {'A': '试题正文', 'B': '试题选项', 'C': '试题答案'},
        {
          'A': '测试题目',
          'B': 'A. 选项一\$;B. 选项二',
          'C': 'Z',
        },
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      // Z 超出选项范围，回退为原始字母
      expect(result.questions[0].answer, 'Z');
    });

    test('国网模板 - 选项分散列布局（单选4项）', () async {
      // 模拟"信息安规-外包人员.xlsx"的布局：
      // G=试题正文, H=试题选项, I=试题答案, J/K=更多选项, L=答案字母
      final xlsx = createXlsx([
        {'G': '试题正文', 'H': '试题选项', 'I': '试题答案', 'J': '', 'K': '', 'L': ''},
        {
          'G': '信息系统故障紧急抢修时，工作票应经谁同意？',
          'H': '工作许可人',
          'I': '工作票签发人',
          'J': '信息运维部门',
          'K': '业务主管部门',
          'L': 'B',
        },
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question,
          contains('信息系统故障紧急抢修时，工作票应经谁同意？'));
      expect(result.questions[0].question, contains('A. 工作许可人'));
      expect(result.questions[0].question, contains('B. 工作票签发人'));
      expect(result.questions[0].question, contains('C. 信息运维部门'));
      expect(result.questions[0].question, contains('D. 业务主管部门'));
      expect(result.questions[0].answer, 'B. 工作票签发人');
    });

    test('国网模板 - 选项分散列布局（多选）', () async {
      final xlsx = createXlsx([
        {'G': '试题正文', 'H': '试题选项', 'I': '试题答案', 'J': '', 'K': '', 'L': ''},
        {
          'G': '以下哪些是编程语言？',
          'H': 'Python',
          'I': 'Flutter',
          'J': 'Java',
          'K': 'Dart',
          'L': 'AC',
        },
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question, contains('以下哪些是编程语言？'));
      expect(result.questions[0].answer, 'A. Python；C. Java');
    });

    test('国网模板 - 选项分散列布局（判断题2项）', () async {
      final xlsx = createXlsx([
        {'G': '试题正文', 'H': '试题选项', 'I': '试题答案', 'J': '', 'K': '', 'L': ''},
        {
          'G': 'Flutter 使用 Dart 语言开发',
          'H': '正确',
          'I': '错误',
          'L': 'A',
        },
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question, contains('Flutter 使用 Dart 语言开发'));
      expect(result.questions[0].question, contains('A. 正确'));
      expect(result.questions[0].question, contains('B. 错误'));
      expect(result.questions[0].answer, 'A. 正确');
    });

    test('通用 XLSX - 无国网表头走通用解析路径', () async {
      final xlsx = createXlsx([
        {'A': 'question', 'B': 'answer'},
        {'A': '普通题目', 'B': '普通答案'},
      ]);
      final result = await FileImportService.importFile(xlsx, 'test.xlsx');
      expect(result.error, isNull);
      expect(result.questions.length, 1);
      expect(result.questions[0].question, '普通题目');
      expect(result.questions[0].answer, '普通答案');
    });
  });

  // ==================== QuestionItem → Question 转换 ====================

  group('FileImportService - toDbQuestions', () {
    test('QuestionItem 应正确转换为 Question（含 explanation）', () {
      final items = [
        QuestionItem(question: '测试题目', answer: '测试答案', explanation: '详细解析'),
      ];
      final questions = FileImportService.toDbQuestions(items, 'bank-1');
      expect(questions.length, 1);
      expect(questions[0].rawText, '测试题目');
      expect(questions[0].answer, '测试答案');
      expect(questions[0].explanation, '详细解析');
      expect(questions[0].bankId, 'bank-1');
      expect(questions[0].id, isNotEmpty);
    });

    test('QuestionItem 无 explanation 时 Question.explanation 应为 null', () {
      final items = [
        QuestionItem(question: '测试题目', answer: '测试答案'),
      ];
      final questions = FileImportService.toDbQuestions(items, 'bank-1');
      expect(questions.length, 1);
      expect(questions[0].explanation, isNull);
    });

    test('preprocessedText 应被正确生成', () {
      final items = [
        QuestionItem(question: 'Hello World', answer: 'Greeting'),
      ];
      final questions = FileImportService.toDbQuestions(items, 'bank-1');
      // 强过滤管线：转换为大写且拼接时不保留空格
      expect(questions[0].preprocessedText, 'HELLOWORLD');
    });

    test('批量转换', () {
      final items = List.generate(
        100,
        (i) => QuestionItem(question: '题目$i', answer: '答案$i'),
      );
      final questions = FileImportService.toDbQuestions(items, 'bank-1');
      expect(questions.length, 100);
      expect(questions[0].createdAt, isNotNull);
    });
  });

  // ==================== 错误处理 ====================

  group('FileImportService - 错误处理', () {
    test('空字节数组', () async {
      final result = await FileImportService.importFile(Uint8List(0), 'test.json');
      expect(result.error, isNotNull);
    });

    test('文件名不含扩展名', () async {
      final result = await FileImportService.importFile(
        toBytes('{"q":"test","a":"ans"}'),
        'NOEXT',
      );
      expect(result.error, contains('不支持的文件格式'));
    });

    test('超大文件不应崩溃', () async {
      // 模拟 10MB 的 JSON
      final largeContent = '[${List.generate(50000, (i) => '{"q":"q$i","a":"a$i"}').join(',')}]';
      final bytes = toBytes(largeContent);
      final stopwatch = Stopwatch()..start();
      final result = await FileImportService.importFile(bytes, 'large.json');
      stopwatch.stop();
      expect(result.error, isNull);
      expect(result.questions.length, 50000);
      // 5 万条应在合理时间内
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });
}

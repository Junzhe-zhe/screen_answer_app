/// 文本预处理单元测试
///
/// 覆盖场景:
/// - 全角→半角转换（数字、字母、标点）
/// - 繁体→简体转换
/// - 大写化
/// - 非字母数字/中文过滤
/// - 空白字符规范化
/// - 选项前缀清理（A. / A、等）
/// - 边界情况：空字符串、纯标点、纯数字
///
/// 说明：preprocess 是强过滤管线（过滤孤立短词、纯数字词、拼接去空格），
/// 纯转换类断言使用轻量的 preprocessRaw（仅转换和基本清理）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_answer_app/utils/text_preprocessor.dart';

void main() {
  group('TextPreprocessor - 全角→半角转换', () {
    test('全角数字应转为半角', () {
      final result = TextPreprocessor.preprocessRaw('０１２３４５６７８９');
      expect(result, '0123456789');
    });

    test('全角大写字母应转为半角', () {
      final result = TextPreprocessor.preprocessRaw('ＡＢＣＤＥＦＧ');
      expect(result, 'ABCDEFG');
    });

    test('全角小写字母应转为半角', () {
      final result = TextPreprocessor.preprocessRaw('ａｂｃｄｅｆｇ');
      expect(result, 'ABCDEFG'); // 转半角后大写化
    });

    test('全角标点应转为半角', () {
      final result = TextPreprocessor.preprocess('（），。；：！？【】｛｝');
      // 标点会被过滤或转为半角
      expect(result, isNot(contains('（')));
      expect(result, isNot(contains('）')));
    });

    test('全角空格应转为半角', () {
      final result = TextPreprocessor.preprocessRaw('全角　空格');
      expect(result, '全角 空格'); // 包含半角空格
    });

    test('混合全角半角应统一', () {
      final result = TextPreprocessor.preprocessRaw('Ｈello Ｗorld');
      expect(result, 'HELLO WORLD');
    });
  });

  group('TextPreprocessor - 繁体→简体转换', () {
    test('繁体字应转为简体', () {
      final result = TextPreprocessor.preprocess('題庫試題');
      expect(result, '题库试题');
    });

    test('常见繁体字转换', () {
      final testCases = {
        '選擇題': '选择题',
        '開放式問題': '开放式问题',
        '計算機網絡': '计算机网络',
        '電子郵件': '电子邮件',
        '國際標準': '国际标准',
      };
      for (final entry in testCases.entries) {
        final result = TextPreprocessor.preprocess(entry.key);
        expect(result, contains(entry.value));
      }
    });

    test('繁简混合文本', () {
      final result = TextPreprocessor.preprocess('這是一個測試題庫');
      expect(result, contains('这是一个测试题库'));
    });

    test('简体文本不应被改变', () {
      final result = TextPreprocessor.preprocess('这是一个测试');
      expect(result, contains('这是一个测试'));
    });
  });

  group('TextPreprocessor - 大写化', () {
    test('英文字母应转为大写', () {
      final result = TextPreprocessor.preprocessRaw('hello world');
      expect(result, 'HELLO WORLD');
    });

    test('已大写的字母保持不变', () {
      final result = TextPreprocessor.preprocessRaw('HELLO WORLD');
      expect(result, 'HELLO WORLD');
    });

    test('混合大小写应统一为大写', () {
      final result = TextPreprocessor.preprocessRaw('Flutter Riverpod');
      expect(result, 'FLUTTER RIVERPOD');
    });
  });

  group('TextPreprocessor - 非字母数字/中文过滤', () {
    test('特殊符号应被替换为空格', () {
      final result = TextPreprocessor.preprocessRaw('hello@world#2024');
      expect(result, 'HELLO WORLD 2024');
    });

    test('emoji 应被过滤', () {
      final result = TextPreprocessor.preprocessRaw('测试😊题目👍');
      expect(result, '测试 题目');
    });

    test('HTML 标签应被过滤', () {
      final result = TextPreprocessor.preprocessRaw('<p>测试内容</p>');
      expect(result, 'P 测试内容 P');
    });

    test('数学符号应被过滤或保留', () {
      // 注意：±、×、÷ 等不在 \w 和 \u4e00-\u9fff 范围内
      final result = TextPreprocessor.preprocessRaw('3×5=15');
      expect(result, '3 5 15');
    });
  });

  group('TextPreprocessor - 空白字符规范化', () {
    test('多个连续空格应合并为一个', () {
      final result = TextPreprocessor.preprocessRaw('hello    world');
      expect(result, 'HELLO WORLD');
    });

    test('首尾空白应被去除', () {
      final result = TextPreprocessor.preprocess('  测试文本  ');
      expect(result, '测试文本');
    });

    test('Tab 和换行应被替换为空格', () {
      final result = TextPreprocessor.preprocessRaw('第一行\t第二行\n第三行');
      expect(result, '第一行 第二行 第三行');
    });
  });

  group('TextPreprocessor - 选项前缀清理', () {
    test('A. 前缀应被去除', () {
      final result = TextPreprocessor.preprocess('A. 这是选项');
      expect(result, '这是选项');
    });

    test('A、前缀应被去除', () {
      final result = TextPreprocessor.preprocess('A、这是选项');
      expect(result, '这是选项');
    });

    test('B. 前缀应被去除', () {
      final result = TextPreprocessor.preprocess('B. 第二个选项');
      expect(result, '第二个选项');
    });

    test('H. 前缀应被去除（H 是最后一个字母）', () {
      final result = TextPreprocessor.preprocess('H. 第八个选项');
      expect(result, '第八个选项');
    });

    test('I. 前缀不应被去除（I 超出 A-H 范围）', () {
      // I 不在 A-H 范围内，前缀清理不处理
      final result = TextPreprocessor.preprocessRaw('I. 第九个选项');
      expect(result, 'I 第九个选项');
    });

    test('无前缀文本保持不变', () {
      final result = TextPreprocessor.preprocess('这是一个普通题目');
      expect(result, '这是一个普通题目');
    });
  });

  group('TextPreprocessor - 边界情况', () {
    test('空字符串应返回空字符串', () {
      final result = TextPreprocessor.preprocess('');
      expect(result, '');
    });

    test('纯空白字符串应返回空字符串', () {
      final result = TextPreprocessor.preprocess('   ');
      expect(result, '');
    });

    test('纯标点符号应返回空字符串', () {
      final result = TextPreprocessor.preprocess('！？，。、；：');
      expect(result, '');
    });

    test('纯数字字符串（强过滤管线视为噪声）', () {
      // preprocess 会过滤纯数字词；转换能力由 preprocessRaw 保证
      expect(TextPreprocessor.preprocess('12345'), '');
      expect(TextPreprocessor.preprocessRaw('12345'), '12345');
    });

    test('纯英文字母（过短视为孤立噪声）', () {
      expect(TextPreprocessor.preprocess('abcdef'), '');
      expect(TextPreprocessor.preprocessRaw('abcdef'), 'ABCDEF');
    });

    test('单字符输入（preprocess 返回空，走 raw 回退）', () {
      expect(TextPreprocessor.preprocess('A'), '');
      expect(TextPreprocessor.preprocessRaw('A'), 'A');
    });

    test('极长文本输入', () {
      final longText = '测试' * 1000;
      final result = TextPreprocessor.preprocess(longText);
      expect(result.length, 2000);
      expect(result, contains('测试'));
    });
  });

  group('TextPreprocessor - 综合场景', () {
    test('典型 OCR 输出预处理', () {
      // OCR 常见输出：全角、繁体、大小写混合
      final ocrOutput = 'Ａ. 下列哪個選項是正確的？\n'
          'B. 這是一個測試\n'
          'Ｃ. 答案可能是C\n'
          'd. 以上皆是';
      final result = TextPreprocessor.preprocess(ocrOutput);
      // 应全部大写、简体、半角、去除选项前缀
      expect(result, isNot(contains('Ａ')));
      expect(result, isNot(contains('個')));
      expect(result, contains('下列哪个选项是正确的'));
      expect(result, contains('这是一个测试'));
      expect(result, contains('答案可能是'));
      expect(result, contains('以上皆是'));
    });

    test('带数字编号的题目', () {
      // 数字前缀不在 A-H 范围内，前缀清理不处理
      final result = TextPreprocessor.preprocessRaw('1. 第一题内容');
      expect(result, '1 第一题内容');
    });

    test('中文与英文混合', () {
      final result = TextPreprocessor.preprocessRaw('TCP/IP 协议是什么？');
      expect(result, 'TCP IP 协议是什么');
    });
  });
}

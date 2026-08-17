class TextPreprocessor {
  static final _fullWidthMap = <String, String>{
    '０': '0', '１': '1', '２': '2', '３': '3', '４': '4',
    '５': '5', '６': '6', '７': '7', '８': '8', '９': '9',
    'Ａ': 'A', 'Ｂ': 'B', 'Ｃ': 'C', 'Ｄ': 'D', 'Ｅ': 'E',
    'Ｆ': 'F', 'Ｇ': 'G', 'Ｈ': 'H', 'Ｉ': 'I', 'Ｊ': 'J',
    'Ｋ': 'K', 'Ｌ': 'L', 'Ｍ': 'M', 'Ｎ': 'N', 'Ｏ': 'O',
    'Ｐ': 'P', 'Ｑ': 'Q', 'Ｒ': 'R', 'Ｓ': 'S', 'Ｔ': 'T',
    'Ｕ': 'U', 'Ｖ': 'V', 'Ｗ': 'W', 'Ｘ': 'X', 'Ｙ': 'Y',
    'Ｚ': 'Z', 'ａ': 'a', 'ｂ': 'b', 'ｃ': 'c', 'ｄ': 'd',
    'ｅ': 'e', 'ｆ': 'f', 'ｇ': 'g', 'ｈ': 'h', 'ｉ': 'i',
    'ｊ': 'j', 'ｋ': 'k', 'ｌ': 'l', 'ｍ': 'm', 'ｎ': 'n',
    'ｏ': 'o', 'ｐ': 'p', 'ｑ': 'q', 'ｒ': 'r', 'ｓ': 's',
    'ｔ': 't', 'ｕ': 'u', 'ｖ': 'v', 'ｗ': 'w', 'ｘ': 'x',
    'ｙ': 'y', 'ｚ': 'z',
    '（': '(', '）': ')', '，': ',', '。': '.', '；': ';',
    '：': ':', '！': '!', '？': '?', '【': '[', '】': ']',
    '｛': '{', '｝': '}', '＝': '=', '＋': '+', ' ': ' ',
  };

  static final _traditionalToSimplified = <String, String>{
    '題': '题', '庫': '库', '試': '试', '業': '业', '務': '务',
    '單': '单', '選': '选', '號': '号', '體': '体', '對': '对',
    '門': '门', '開': '开', '關': '关', '電': '电', '網': '网',
    '萬': '万', '個': '个', '時': '时', '會': '会', '機': '机',
    '學': '学', '實': '实', '專': '专', '圖': '图', '點': '点',
    '當': '当', '為': '为', '從': '从', '長': '长', '動': '动',
    '義': '义', '數': '数', '國': '国', '際': '际', '標': '标',
    '畫': '画', '區': '区', '難': '难', '頭': '头', '髮': '发',
    '歷': '历', '術': '术', '線': '线', '結': '结', '統': '统',
    '規': '规', '經': '经', '質': '质', '進': '进', '證': '证',
    '擇': '择', '測': '测',
    '項': '项', '確': '确', '認': '认',
    '讓': '让', '該': '该', '說': '说', '話': '话', '讀': '读',
    '書': '书', '寫': '写', '見': '见', '風': '风', '雲': '云',
    '愛': '爱', '親': '亲', '東': '东', '樂': '乐', '興': '兴',
    '計': '计', '絡': '络', '較': '较', '運': '运',
    '態': '态', '異': '异', '議': '议', '響': '响', '應': '应',
    '郵': '邮', '準': '准', '這': '这', '問': '问',
    '熱': '热', '屆': '届', '責': '责', '範': '范',
    // OCR 常见繁体补充（题库/考试界面高频字，原表未覆盖）
    '據': '据', '險': '险', '練': '练', '習': '习',
    '斷': '断', '層': '层', '檢': '检', '份': '份',
    '參': '参', '權': '权', '護': '护', '環': '环',
    '預': '预', '資': '资', '儲': '储', '記': '记',
    '錄': '录', '載': '载', '稱': '称', '語': '语',
    '複': '复', '雜': '杂', '類': '类', '碼': '码',
    '節': '节', '約': '约', '訪': '访', '審': '审',
    '核': '核', '圍': '围', '顯': '显', '輸': '输',
    '錯': '错', '誤': '误', '警': '警', '告': '告',
    '限': '限', '示': '示', '出': '出',
  };

  /// 已知的 UI 噪声关键词（来自考试页面元素）
  /// 注意：太短的关键词（如"选""全"）会在 Phase 2 按行过滤时触发，应避免使用
  static final _noiseKeywords = <String>{
    // 考试页面 UI 元素（较长、不太可能出现在题目中的关键词）
    '倒计时', '交卷', '剩余时间', '答题卡',
    '上一题', '下一题', '提交提交', '返回列表',
    '单选题', '多选题', '判断题', '填空题',
    // 题库首页/导航元素（OCR 在非题目页面触发时会识别到）
    '会员中心', '随机练习', '题型练习', '章节练习', '顺序练习',
    '模拟考试', '去考试', '精简题', '易错题', '考点速记', '试题搜索',
    // 注意：保命题/坦本安 等标记在 Phase 1 用正则子串移除（它们常与题干同行，整行过滤会误删题干）
    // 注意：OCR 题型标签乱码（"2斩题 多造" 等）在 Phase 1 用正则子串移除，
    // 不能放进这里——_noiseKeywords 是整行过滤，会误删同行题干。
  };

  /// 轻量预处理：仅做半角/简体转换和基本清理，不过滤噪声。
  /// 用于 preprocess 结果为空时的回退匹配。
  static String preprocessRaw(String text) {
    if (text.isEmpty) return '';
    var result = text;
    result = _toHalfWidth(result);
    result = _toSimplified(result);
    result = result.toUpperCase();
    // 去除非中文/字母数字的符号
    result = result.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  static String preprocess(String text) {
    if (text.isEmpty) return '';
    var result = text;
    result = _toHalfWidth(result);
    result = _toSimplified(result);
    result = result.toUpperCase();

    // === Phase 1: 考试页面 UI 模式清理（在分行前处理，因为是行内噪声） ===

    // 1.1 倒计时模式： "O倒计时 00:39:28", "倒计时 00:39:28(交卷"
    result = result.replaceAll(RegExp(r'[0O]?\s*倒计时[\s　]*\d{1,2}[\.:：]\d{2}(?:[\.:：]\d{2})?'), '');
    // 1.2 交卷按钮： "(交卷" 或 "交卷)"
    result = result.replaceAll(RegExp(r'[\(（【]\s*交卷\s*[\)）】]?'), '');
    result = result.replaceAll(RegExp(r'交卷\s*'), '');
    // 1.3 独立时间字符串 "00:39:28"
    result = result.replaceAll(RegExp(r'\b\d{1,2}[:：]\d{2}[:：]\d{2}\b'), '');
    // 1.4 "选," 或 "选，" 作为选项区指示
    result = result.replaceAll(RegExp(r'选\s*[,，]'), '');
    // 1.5 连续的选项字母标记 "A B C D" 或 "A  B  C  D"
    result = result.replaceAll(RegExp(r'\b([A-D])\s*(?=[A-D]\s*[A-D])'), '');
    // 1.6 尾部的孤立选项字母： " D" 或 " A" 在行末
    result = result.replaceAll(RegExp(r'\s+[A-D](?=\s*$)', multiLine: true), '');
    // 1.7 OCR 题型标签乱码子串："多选题"→"2斩题 多造"、"服漫食丁旨力" 等
    //     仅移除乱码片段本身，保留题干（不能整行丢弃）
    result = result.replaceAll(RegExp(r'斩\s*题'), '');
    result = result.replaceAll(RegExp(r'多造|多逸'), '');
    result = result.replaceAll(RegExp(r'服漫食丁旨力|漫食丁旨力'), '');
    // 行首独立"多选/单选/判断"题型标签（OCR 常与题干同行）
    result = result.replaceAll(RegExp(r'^\s*多\s*选\s*', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\s*单\s*选\s*', multiLine: true), '');
    result = result.replaceAll(RegExp(r'^\s*判\s*断\s*', multiLine: true), '');
    // 1.8 OCR 高频错字纠正（基于真机日志收集：MLKit 中文识别常见误字）
    //     注意顺序：先纠正长词再纠正单字，避免误伤
    result = result.replaceAll('业务教据', '业务数据');
    result = result.replaceAll('运行叁数', '运行参数');
    result = result.replaceAll('叁数', '参数');
    result = result.replaceAll('模拟孝试', '模拟考试');
    result = result.replaceAll('去孝试', '去考试');
    result = result.replaceAll('负贵人', '负责人');
    result = result.replaceAll('负麦人', '负责人');
    result = result.replaceAll('遵宁', '遵守');
    result = result.replaceAll('指辉', '指挥');
    result = result.replaceAll('请楚', '清楚');
    result = result.replaceAll('安全搭施', '安全措施');
    result = result.replaceAll('安全指施', '安全措施');
    result = result.replaceAll('签各', '签名');
    result = result.replaceAll('簽名', '签名');
    result = result.replaceAll('上簽名', '上签名');
    result = result.replaceAll('范国', '范围');
    result = result.replaceAll('作业范', '作业范');
    result = result.replaceAll('貴任', '责任');
    result = result.replaceAll('青任', '责任');
    result = result.replaceAll('教据', '数据');
    result = result.replaceAll('業務', '业务');
    // 1.9 题目列表标记子串移除（与题干同行，不能整行删）
    result = result.replaceAll(RegExp(r'[★☆]\s*\(?\s*保命?题?\s*\)?'), '');
    result = result.replaceAll(RegExp(r'坦本安|基本安|本安规'), '');
    result = result.replaceAll(RegExp(r'会员中心|随机练习|题型练习|章节练习|顺序练习|模拟考试|去考试|精简题|易错题|考点速记|试题搜索'), '');
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // === Phase 2: 按行过滤 ===
    final lines = result.split('\n');
    final filtered = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 3) continue; // 太短的行跳过
      if (_noiseKeywords.any((k) => trimmed.contains(k))) continue; // 已知噪声跳过
      // 如果整行主要是空格/标点和孤立字母，跳过
      if (trimmed.replaceAll(RegExp(r'[A-D\s.,;:!?、。，；：！？\-\+*/=()（）【】\[\]]'), '').length < 3) continue;
      filtered.add(trimmed);
    }
    result = filtered.join('\n');

    // === Phase 3: 选项前缀和标点清理 ===
    // 每行开头的选项前缀 "A. ", "B、 " 等
    result = result.replaceAll(RegExp(r'^[A-H]\s*[\.、．\.]\s*', multiLine: true), '');
    // 非中文/非字母数字 → 空格
    result = result.replaceAll(RegExp(r'[^\w\u4e00-\u9fff]'), ' ');
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    // === Phase 4: 按词过滤孤立噪声 ===
    final words = result.split(' ');
    final meaningful = <String>[];
    for (final word in words) {
      final w = word.trim();
      if (w.isEmpty) continue;
      // 过滤纯数字
      if (RegExp(r'^\d+$').hasMatch(w)) continue;
      // 过滤不含中文的短词（≤3字母且无中文，如 "A" "WIFI" 偶尔是误识别）
      if (w.length <= 3 && !RegExp(r'[\u4e00-\u9fff]').hasMatch(w)) continue;
      // 过滤噪声关键词
      if (_noiseKeywords.any((k) => w == k || w.contains(k))) continue;
      meaningful.add(w);
    }

    // 将过滤后的词直接拼接（不保留空格），有利于模糊匹配
    result = meaningful.join('');

    // 如果过滤后结果太短，返回空让调用方使用原始文本
    return result.length < 3 ? '' : result;
  }

  static String _toHalfWidth(String text) {
    return text.split('').map((c) => _fullWidthMap[c] ?? c).join();
  }

  static String _toSimplified(String text) {
    return text.split('').map((c) => _traditionalToSimplified[c] ?? c).join();
  }
}

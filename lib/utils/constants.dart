import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF2196F3);
  static const Color secondary = Color(0xFF64B5F6);

  // 置信度颜色
  static const Color confidenceHigh = Color(0xFF4CAF50);
  static const Color confidenceMedium = Color(0xFFFFC107);
  static const Color confidenceLow = Color(0xFFF44336);
}

class AppConstants {
  static const String appName = '屏幕答题助手';
  static const String channelBase = 'com.screenanswer';

  // Platform Channel names
  static const String captureChannel = '$channelBase/capture';
  static const String floatChannel = '$channelBase/float';
  static const String recognitionChannel = '$channelBase/recognition';
}

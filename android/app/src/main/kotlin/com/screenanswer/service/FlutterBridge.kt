package com.screenanswer.service

import io.flutter.plugin.common.BinaryMessenger

/**
 * 桥接对象：缓存 Flutter Engine 的 BinaryMessenger，
 * 使独立运行的 FloatService（前台悬浮窗服务）能与原生侧建立 MethodChannel
 * 双向通信，将 OCR 文本回传给 Dart 端的匹配引擎。
 */
object FlutterBridge {
    var messenger: BinaryMessenger? = null
}

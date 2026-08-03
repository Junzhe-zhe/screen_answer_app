package com.screenanswer.screen_answer_app

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.screenanswer.service.FloatService
import com.screenanswer.service.FlutterBridge

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainAct"
        private const val REQ_PROJ = 1001
    }

    private var pendingResultCode = 0
    private var pendingData: Intent? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 缓存 Flutter 的 messenger，供独立运行的 FloatService 与原生双向通信
        FlutterBridge.messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.screenanswer/float")
            .setMethodCallHandler { call, result ->
                if (call.method == "showBall") {
                    Log.e(TAG, "showBall: pendingRc=$pendingResultCode pendingData=$pendingData")
                    if (pendingResultCode != 0 && pendingData != null) {
                        Log.e(TAG, "showBall: reusing cached projection data")
                        startFloatService(pendingResultCode, pendingData!!)
                    } else {
                        Log.e(TAG, "showBall: requesting new projection")
                        requestProjection()
                    }
                    result.success(true)
                } else if (call.method == "hideBall") {
                    stopFloatService()
                    result.success(true)
                } else result.notImplemented()
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.screenanswer/capture")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> result.success(
                        if (Build.VERSION.SDK_INT >= 23) Settings.canDrawOverlays(this) else true
                    )
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.screenanswer/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openOverlaySettings" -> { openOverlaySettings(); result.success(true) }
                    "openAppSettings" -> { openAppSettings(); result.success(true) }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        Log.e(TAG, "onActivityResult: req=$requestCode rc=$resultCode data=$data")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_PROJ && resultCode == Activity.RESULT_OK && data != null) {
            Log.e(TAG, "projection granted! rc=$resultCode")
            pendingResultCode = resultCode
            pendingData = data
            // 杀掉旧 FloatService（如果有），确保新 intent 被 onStartCommand 接收
            stopService(Intent(this, FloatService::class.java))
            startFloatService(resultCode, data)
        } else {
            Log.e(TAG, "projection not granted or cancelled")
        }
    }

    private fun requestProjection() {
        val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(pm.createScreenCaptureIntent(), REQ_PROJ)
    }

    private fun startFloatService(resultCode: Int, data: Intent) {
        val intent = Intent(this, FloatService::class.java).apply {
            putExtra(FloatService.EXTRA_RESULT_CODE, resultCode)
            putExtra(FloatService.EXTRA_DATA, data)
        }
        Log.e(TAG, "startFloatService: rc=$resultCode")
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
        else startService(intent)
    }

    private fun stopFloatService() {
        stopService(Intent(this, FloatService::class.java))
        pendingResultCode = 0; pendingData = null
    }

    private fun openOverlaySettings() {
        try { startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        catch (_: Exception) { openAppSettings() }
    }

    private fun openAppSettings() {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName"); addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
    }
}
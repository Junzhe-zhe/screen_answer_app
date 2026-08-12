package com.screenanswer.service

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object DiagnosticLogger {
    private const val TAG = "ScreenDiag"
    private const val MAX_BYTES = 2L * 1024L * 1024L
    private val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    @Synchronized
    fun log(context: Context?, stage: String, message: String, error: Throwable? = null) {
        val line = buildString {
            append(formatter.format(Date()))
            append(" [").append(Thread.currentThread().name).append("] [")
            append(stage).append("] ").append(message)
            if (error != null) {
                append(" | ").append(error::class.java.simpleName).append(": ")
                append(error.message ?: "")
                append("\n").append(Log.getStackTraceString(error))
            }
            append("\n")
        }
        Log.e(TAG, line.trimEnd())
        try {
            val file = context?.getFileStreamPath("diagnostic-native.log") ?: return
            if (file.exists() && file.length() > MAX_BYTES) file.writeText("")
            file.appendText(line)
        } catch (writeError: Exception) {
            Log.e(TAG, "write diagnostic log failed", writeError)
        }
    }

    /// 读取 diagnostic-native.log 内容，供 Flutter 设置页展示
    fun readLog(context: Context?): String {
        return try {
            val file = context?.getFileStreamPath("diagnostic-native.log") ?: return ""
            if (file.exists()) file.readText() else ""
        } catch (e: Exception) {
            Log.e(TAG, "read diagnostic log failed", e)
            ""
        }
    }
}

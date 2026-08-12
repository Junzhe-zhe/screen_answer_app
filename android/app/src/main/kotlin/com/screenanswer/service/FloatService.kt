package com.screenanswer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.DisplayMetrics
import android.util.Log
import android.view.*
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import com.screenanswer.screen_answer_app.MainActivity
import io.flutter.embedding.engine.FlutterEngineCache

class FloatService : Service() {
    companion object {
        private const val TAG = "FloatService"
        private const val CHANNEL_ID = "fch"
        private const val NOTIFY_ID = 1001
        const val EXTRA_RESULT_CODE = "rc"
        const val EXTRA_DATA = "data"
    }

    private var wm: WindowManager? = null
    private var ball: View? = null
    private var ballParams: WindowManager.LayoutParams? = null
    private var selView: View? = null
    private var selParams: WindowManager.LayoutParams? = null
    private var ansView: View? = null
    private var ansParams: WindowManager.LayoutParams? = null
    private var ansContent: String = ""
    private var ansContentTv: TextView? = null
    private var ansTitleTv: TextView? = null
    private var answerSummary: String = "正确答案：--"
    private var selAnswerTv: TextView? = null
    private var lastAutoQuestionSignature: String = ""
    private var pendingAutoQuestionSignature: String? = null
    private var pendingForceRefresh = false

    private var selX = 100; private var selY = 200
    private var selW = 1080; private var selH = 600
    private var screenW = 1080; private var screenH = 2400
    private var selVisible = false
    private var ansVisible = false

    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null
    private val handler = Handler(Looper.getMainLooper())

    // 与 Flutter 匹配引擎的双向通道
    private var recognitionChannel: MethodChannel? = null
    private var recognitionGeneration = 0L
    private var activeRecognitionGeneration = 0L
    private var recognitionInFlight = false
    private var recognitionTimeout: Runnable? = null
    private var previousUncaughtHandler: Thread.UncaughtExceptionHandler? = null

    private fun diag(stage: String, message: String, error: Throwable? = null) {
        DiagnosticLogger.log(this, stage, message, error)
    }

    // 候选答案列表与当前索引（左右滑动切换）
    private var candidates: List<Candidate> = emptyList()
    private var candidateIndex = 0

    private val textRecognizer by lazy {
        TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
    }

    override fun onCreate() {
        super.onCreate()
        FlutterBridge.service = this
        previousUncaughtHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            diag("uncaught", "thread=${thread.name} generation=$activeRecognitionGeneration inFlight=$recognitionInFlight", error)
            previousUncaughtHandler?.uncaughtException(thread, error)
        }
        diag("service-create", "screen initialization started")
        val dm = DisplayMetrics()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm?.defaultDisplay?.getRealMetrics(dm)
        screenW = dm.widthPixels; screenH = dm.heightPixels
        selW = screenW - 40; selH = 600
        selX = 20; selY = (screenH * 0.15).toInt()
        loadPersistedSettings()
        createChannel(); startFg(); createBall()
        diag("service-create", "screen=${screenW}x${screenH} overlay created")
        setupRecognitionChannel()
    }

    private fun setupRecognitionChannel() {
        // 优先使用 MainActivity 缓存的 messenger；Activity 销毁后
        // FlutterBridge.messenger 可能仍持有有效引用，否则从引擎缓存兜底。
        val m = FlutterBridge.messenger ?: run {
            try {
                FlutterEngineCache.getInstance()
                    .get(MainActivity.ENGINE_ID)
                    ?.dartExecutor?.binaryMessenger
            } catch (e: Exception) {
                Log.w(TAG, "recognitionChannel: engine cache lookup failed", e)
                null
            }
        }
        if (m != null) {
            recognitionChannel = MethodChannel(m, "com.screenanswer/recognition")
            recognitionChannel?.setMethodCallHandler { call, result ->
                if (call.method == "result") {
                    try {
                        val text = call.argument<String>("text") ?: ""
                        val answer = call.argument<String>("answer") ?: ""
                        val explanation = call.argument<String>("explanation") ?: ""
                        val level = call.argument<String>("level") ?: ""
                        val returnedGeneration = (call.argument<Number>("generation"))?.toLong() ?: 0L
                        val candsRaw = call.argument<List<*>>("candidates") ?: emptyList<Any>()
                        handler.post {
                            if (returnedGeneration != activeRecognitionGeneration || !recognitionInFlight) {
                                return@post
                            }
                            recognitionInFlight = false
                            recognitionTimeout?.let { handler.removeCallbacks(it) }
                            recognitionTimeout = null
                            candidates = candsRaw.mapNotNull {
                                val m = it as? Map<*, *> ?: return@mapNotNull null
                                Candidate(
                                    question = m["question"] as? String ?: "",
                                    answer = m["answer"] as? String ?: "",
                                    explanation = m["explanation"] as? String ?: "",
                                    score = (m["score"] as? Number)?.toDouble() ?: 0.0
                                )
                            }
                            candidateIndex = 0
                            val questionSignature = pendingAutoQuestionSignature
                                ?: normalizeQuestionSignature(text)
                            val shouldRefresh = pendingForceRefresh ||
                                questionSignature.isEmpty() ||
                                questionSignature != lastAutoQuestionSignature
                            if (shouldRefresh) {
                                answerSummary = formatAnswerSummary(answer, level)
                                ansContent = formatResult(text, answer, explanation, level, candidates, candidateIndex)
                                selAnswerTv?.text = answerSummary
                                selAnswerTv?.visibility = View.VISIBLE
                                lastAutoQuestionSignature = questionSignature
                                refreshAnswerPanel()
                            }
                            pendingAutoQuestionSignature = null
                            pendingForceRefresh = false
                            // 识别结果返回后重新开启帧监控，持续响应屏幕滑动切题
                            startMonitoring()
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "recognitionChannel: result handler error", e)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        } else {
            Log.w(TAG, "recognitionChannel: FlutterBridge.messenger is null, retrying in 500ms")
            handler.postDelayed({ setupRecognitionChannel() }, 500)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val rc = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
        if (rc != 0) {
            val data: Intent? = if (Build.VERSION.SDK_INT >= 33)
                intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
            else @Suppress("DEPRECATION") intent?.getParcelableExtra(EXTRA_DATA)
            if (data != null) {
                try {
                    val pm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    mediaProjection = pm.getMediaProjection(rc, data)
                    val dm = DisplayMetrics()
                    wm?.defaultDisplay?.getRealMetrics(dm)
                    screenW = dm.widthPixels; screenH = dm.heightPixels; selW = screenW - 40
                    toast("projection OK ${screenW}x${screenH}")
                } catch (e: Exception) { toast("projection FAIL: ${e.message}") }
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        diag("service-destroy", "generation=$activeRecognitionGeneration inFlight=$recognitionInFlight captureSetup=$captureSetupDone")
        FlutterBridge.service = null
        super.onDestroy()
        stopMonitoring()
        recognitionChannel = null
        try { ball?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { selView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        try { ansView?.let { wm?.removeView(it) } } catch (_: Exception) {}
        cleanupCapture()
        try { mediaProjection?.unregisterCallback(projectionCallback) } catch (_: Exception) {}
        try { mediaProjection?.stop() } catch (_: Exception) {}
    }

    private fun toast(msg: String) = handler.post { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show() }

    private fun createChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "F", NotificationManager.IMPORTANCE_LOW))
    }

    private fun startFg() {
        val n = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("\u5c4f\u5e55\u7b54\u9898\u52a9\u624b").setContentText("\u60ac\u6d6e\u7403\u8fd0\u884c\u4e2d")
            .setSmallIcon(android.R.drawable.ic_menu_camera).setOngoing(true).build()
        try {
            if (Build.VERSION.SDK_INT >= 34)
                startForeground(NOTIFY_ID, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            else startForeground(NOTIFY_ID, n)
        } catch (e: Exception) { startForeground(NOTIFY_ID, n) }
    }

    // ====== Floating ball ======

    private fun createBall(startX: Int = 50, startY: Int = 500) {
        val sz = (ballSizeDp * resources.displayMetrics.density).toInt()
        val typ = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        ballParams = WindowManager.LayoutParams(sz, sz, typ,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START; x = startX; y = startY }

        ball = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL; setStroke(borderWidthDp.toInt(), 0xFFFFFFFF.toInt()); setColor(0x00000000)
            }
            setOnTouchListener(object : View.OnTouchListener {
                var ix = 0f; var iy = 0f; var px = 0; var py = 0; var mv = false
                override fun onTouch(v: View, e: MotionEvent): Boolean {
                    when (e.action) {
                        MotionEvent.ACTION_DOWN -> { ix = e.rawX; iy = e.rawY; px = ballParams!!.x; py = ballParams!!.y; mv = false; return true }
                        MotionEvent.ACTION_MOVE -> {
                            val dx = (e.rawX - ix).toInt(); val dy = (e.rawY - iy).toInt()
                            if (Math.abs(dx) > 5 || Math.abs(dy) > 5) mv = true
                            ballParams!!.x = px + dx; ballParams!!.y = py + dy
                            wm?.updateViewLayout(v, ballParams); return true
                        }
                        MotionEvent.ACTION_UP -> { if (!mv) toggleAnswer(); return true }
                    }
                    return false
                }
            })
        }
        wm!!.addView(ball, ballParams)
    }

    // ====== Answer panel ======

    private fun toggleAnswer() {
        if (ansVisible) { hideAnswer(); return }
        showAnswer()
    }

    private fun showAnswer() {
        hideSel(); ansVisible = true
        ansView?.let {
            it.visibility = View.VISIBLE
            refreshTextOnly()
            // 始终启动监控，确保后续屏幕滑动能触发重新识别
            startMonitoring()
            return
        }

        val typ = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

        val aw = screenW - 40; val ah = (screenH * 0.55).toInt()
        ansParams = WindowManager.LayoutParams(aw, ah, typ,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20; y = (screenH * 0.12).toInt()
        }

        val density = resources.displayMetrics.density
        val titleH = (48 * density).toInt()
        val resizeSz = (44 * density).toInt()

        // 横向滑动检测：存在候选列表时左右滑动切换候选；无候选时左右滑动重新识别。
        // 在容器 dispatchTouchEvent 中手动跟踪 down/up 位移，始终 return super 不阻断子 View 交互。
        var swipeDownX = 0f; var swipeDownY = 0f; var swipeDownTime = 0L

        val container = object : FrameLayout(this@FloatService) {
            override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
                when (ev.action) {
                    MotionEvent.ACTION_DOWN -> {
                        swipeDownX = ev.x; swipeDownY = ev.y; swipeDownTime = System.currentTimeMillis()
                    }
                    MotionEvent.ACTION_UP -> {
                        val rawDx = ev.x - swipeDownX
                        val dx = Math.abs(rawDx)
                        val dy = Math.abs(ev.y - swipeDownY)
                        val dt = System.currentTimeMillis() - swipeDownTime
                        // 起点位于标题栏或底栏区域时不触发，避免与拖拽/按钮/缩放冲突
                        val inTitle = swipeDownY < titleH
                        val inBottom = ansParams != null && swipeDownY > (ansParams!!.height - resizeSz)
                        if (!inTitle && !inBottom && dx > dy * 1.2f && dx > 30 * density && dt < 1200) {
                            handler.post {
                                if (candidates.isNotEmpty()) {
                                    // 候选切换：左滑（rawDx<0）下一个，右滑（rawDx>0）上一个
                                    val dir = if (rawDx < 0) 1 else -1
                                    val newIdx = candidateIndex + dir
                                    if (newIdx in 0 until candidates.size) {
                                        candidateIndex = newIdx
                                        ansContent = formatResult("", "", "", "none", candidates, candidateIndex, fromCandidate = true)
                                        refreshAnswerPanel()
                                    }
                                } else {
                                    performRecognition(autoRecognize = true)
                                }
                            }
                        }
                    }
                }
                return super.dispatchTouchEvent(ev)
            }
        }.apply {
            background = GradientDrawable().apply {
                setColor(0xEE2A2A35.toInt()); cornerRadius = 16f; setStroke(1, 0x55FFFFFF.toInt())
            }

            // 1) 内容 ScrollView：仅负责纵向滚动，横向滑动交给面板级 GestureDetector
            val scrollView = ScrollView(this@FloatService).apply {
                isVerticalScrollBarEnabled = true
                setPadding((16 * density).toInt(), titleH + (8 * density).toInt(), (16 * density).toInt(), (resizeSz + 4 * density).toInt())
            }
            val contentTv = TextView(this@FloatService).apply {
                id = View.generateViewId(); tag = "ansContent"
                setText(ansContent.ifEmpty { "\u8bf7\u70b9\u51fb\u4e0b\u65b9\u300c\u6846\u9009\u300d\u6309\u94ae\u9009\u53d6\u9898\u76ee" })
                setTextColor(0xFFE8E8EE.toInt()); textSize = 14f; setLineSpacing(6f, 1f)
            }
            ansContentTv = contentTv
            scrollView.addView(contentTv)
            addView(scrollView, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))

            // 2) 顶部标题栏：左侧图标 + 标题 + 右侧关闭；整栏可拖拽
            val titleBar = FrameLayout(this@FloatService).apply {
                background = GradientDrawable().apply {
                    setColor(0xFF383845.toInt())
                    cornerRadii = floatArrayOf(16f*density, 16f*density, 16f*density, 16f*density, 0f, 0f, 0f, 0f)
                }
                // 左侧「设置题目区域」按钮
                val cropTv = TextView(this@FloatService).apply {
                    setText("\u8bbe\u7f6e\u9898\u76ee\u533a\u57df"); setTextColor(0xFFFFA07A.toInt()); textSize = 13f; gravity = Gravity.CENTER
                    setPadding((12 * density).toInt(), 0, (8 * density).toInt(), 0)
                    setOnClickListener { hideAnswer(); showSel() }
                }
                addView(cropTv, FrameLayout.LayoutParams((96 * density).toInt(), titleH, Gravity.START or Gravity.CENTER_VERTICAL))

                // 标题
                val titleTv = TextView(this@FloatService).apply {
                    id = View.generateViewId(); tag = "ansTitle"
                    setText(answerSummary); setTextColor(0xFFFFFFFF.toInt()); textSize = 14f
                    gravity = Gravity.CENTER; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding((100 * density).toInt(), 0, (44 * density).toInt(), 0)
                }
                ansTitleTv = titleTv
                addView(titleTv, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, titleH, Gravity.CENTER))

                // 关闭按钮
                val closeTv = TextView(this@FloatService).apply {
                    setText("\u2715"); setTextColor(0xFFBBBBBB.toInt()); textSize = 18f; gravity = Gravity.CENTER
                    setPadding((12 * density).toInt(), 0, (12 * density).toInt(), 0)
                    setOnClickListener { hideAnswer() }
                }
                addView(closeTv, FrameLayout.LayoutParams((44 * density).toInt(), titleH, Gravity.END or Gravity.CENTER_VERTICAL))

                // 拖拽监听
                setOnTouchListener(object : View.OnTouchListener {
                    var downX = 0f; var downY = 0f; var px = 0; var py = 0; var moved = false
                    override fun onTouch(v: View, e: MotionEvent): Boolean {
                        when (e.action) {
                            MotionEvent.ACTION_DOWN -> {
                                downX = e.rawX; downY = e.rawY
                                px = ansParams!!.x; py = ansParams!!.y
                                moved = false
                                return true
                            }
                            MotionEvent.ACTION_MOVE -> {
                                val dx = (e.rawX - downX).toInt()
                                val dy = (e.rawY - downY).toInt()
                                if (Math.abs(dx) > 3 || Math.abs(dy) > 3) moved = true
                                ansParams!!.x = px + dx; ansParams!!.y = py + dy
                                wm?.updateViewLayout(ansView, ansParams)
                                return true
                            }
                            MotionEvent.ACTION_UP -> return moved
                        }
                        return false
                    }
                })
            }
            addView(titleBar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, titleH, Gravity.TOP))

            // 3) 底部工具栏：左下角重新识别 + 复制，右下角缩放
            val bottomBar = FrameLayout(this@FloatService).apply {
                // 重新识别按钮
                val retryTv = TextView(this@FloatService).apply {
                    setText("\u26a1"); setTextColor(0xFFBBBBBB.toInt()); textSize = 20f; gravity = Gravity.CENTER
                    setPadding((12 * density).toInt(), 0, (12 * density).toInt(), 0)
                    setOnClickListener { performRecognition(autoRecognize = false) }
                }
                addView(retryTv, FrameLayout.LayoutParams((44 * density).toInt(), resizeSz, Gravity.START or Gravity.BOTTOM))

                // 缩放区域（整个右下角容器都可触摸，不只是图标）
                val resizeContainer = FrameLayout(this@FloatService).apply {
                    val resizeIcon = TextView(this@FloatService).apply {
                        setText("\u26f6"); setTextColor(0xFFBBBBBB.toInt()); textSize = 18f; gravity = Gravity.CENTER
                    }
                    addView(resizeIcon, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                    setOnTouchListener(object : View.OnTouchListener {
                        var downX = 0f; var downY = 0f; var startW = 0; var startH = 0
                        override fun onTouch(v: View, e: MotionEvent): Boolean {
                            when (e.action) {
                                MotionEvent.ACTION_DOWN -> {
                                    downX = e.rawX; downY = e.rawY
                                    startW = ansParams!!.width; startH = ansParams!!.height
                                    return true
                                }
                                MotionEvent.ACTION_MOVE -> {
                                    val dx = (e.rawX - downX).toInt()
                                    val dy = (e.rawY - downY).toInt()
                                    val minW = (200 * density).toInt(); val minH = (200 * density).toInt()
                                    ansParams!!.width = (startW + dx).coerceIn(minW, screenW)
                                    ansParams!!.height = (startH + dy).coerceIn(minH, screenH)
                                    wm?.updateViewLayout(ansView, ansParams)
                                    return true
                                }
                                MotionEvent.ACTION_UP -> return true
                            }
                            return false
                        }
                    })
                }
                addView(resizeContainer, FrameLayout.LayoutParams(resizeSz, resizeSz, Gravity.END or Gravity.BOTTOM))
            }
            addView(bottomBar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, resizeSz, Gravity.BOTTOM))

        }
        ansView = container; wm!!.addView(container, ansParams)
    }

    /// 仅刷新文字，不重建视图
    private fun refreshAnswerPanel() {
        val v = ansView ?: return
        if (!ansVisible) {
            showAnswer()
            return
        }
        refreshTextOnly()
        // 不再在此处调用 startMonitoring()，避免每次刷新都重启监控导致闪烁
        // 监控仅在 showAnswer() 首次创建视图时启动
    }

    private fun refreshTextOnly() {
        ansContentTv?.text = ansContent
        ansTitleTv?.text = answerSummary
        selAnswerTv?.text = answerSummary
    }

    private fun extractTitle(content: String): String {
        if (content.isEmpty()) return "\u7b54\u6848\u9762\u677f"
        val lines = content.split('\n')
        for (line in lines) {
            val t = line.trim()
            if (t.isNotEmpty() && !t.startsWith("\u3010") && !t.startsWith("\u2713") && !t.startsWith("\u2501")) {
                return if (t.length > 20) t.take(20) + "..." else t
            }
        }
        return "\u7b54\u6848\u9762\u677f"
    }

    private fun hideAnswer() {
        stopMonitoring()
        ansView?.visibility = View.GONE; ansVisible = false
    }

    // ====== Selection area ======

    private var selAutoTimer: Runnable? = null

    private fun showSel() {
        if (selView != null) { selView!!.visibility = View.VISIBLE; selVisible = true; return }
        toast("拖动调整选框范围，松手自动识别")
        val typ = if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE
        selParams = WindowManager.LayoutParams(selW, selH, typ,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.TOP or Gravity.START; x = selX; y = selY }

        val container = FrameLayout(this@FloatService).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE; setColor(0x33888888.toInt())
                setStroke(borderWidthDp.toInt(), 0xFF888888.toInt()); cornerRadius = 12f
            }
            // 注意：选框浮层不再显示任何文字，避免被截图 OCR 误识别（提示改为 Toast）

            val hs = (24 * resources.displayMetrics.density).toInt()
            addView(View(this@FloatService).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL; setColor(0xFF888888.toInt()); setStroke(1, 0xFFCCCCCC.toInt())
                }
            }, FrameLayout.LayoutParams(hs, hs, Gravity.BOTTOM or Gravity.END).apply { setMargins(0, 0, 8, 8) })

            setOnTouchListener(object : View.OnTouchListener {
                var downX = 0f; var downY = 0f; var px = 0; var py = 0
                var startW = 0; var startH = 0; var isResizing = false; var moved = false
                val EDGE = 40
                override fun onTouch(v: View, e: MotionEvent): Boolean {
                    when (e.action) {
                        MotionEvent.ACTION_DOWN -> {
                            selAutoTimer?.let { handler.removeCallbacks(it) }
                            downX = e.rawX; downY = e.rawY; px = selParams!!.x; py = selParams!!.y
                            startW = selW; startH = selH; moved = false
                            val edgePx = (EDGE * resources.displayMetrics.density).toInt()
                            isResizing = (selW - e.x < edgePx && selH - e.y < edgePx)
                            return true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val dx = (e.rawX - downX).toInt(); val dy = (e.rawY - downY).toInt()
                            if (Math.abs(dx) > 8 || Math.abs(dy) > 8) moved = true
                            if (isResizing) {
                                val minSz = (80 * resources.displayMetrics.density).toInt()
                                selW = (startW + dx).coerceIn(minSz, screenW)
                                selH = (startH + dy).coerceIn(minSz, screenH)
                                selParams!!.width = selW; selParams!!.height = selH
                                wm?.updateViewLayout(v, selParams)
                            } else {
                                selParams!!.x = px + dx; selParams!!.y = py + dy
                                selX = selParams!!.x; selY = selParams!!.y
                                wm?.updateViewLayout(v, selParams)
                            }
                            return true
                        }
                        MotionEvent.ACTION_UP -> {
                            selAutoTimer = Runnable { performRecognition() }
                            selAutoTimer?.let { handler.postDelayed(it, 600) }
                            return true
                        }
                    }
                    return false
                }
            })
        }
        selView = container; wm!!.addView(selView, selParams); selVisible = true
        ball?.let { wm?.removeView(it) }; ball?.let { wm?.addView(it, ballParams) }
    }

    private fun hideSel() {
        selAutoTimer?.let { handler.removeCallbacks(it) }; selAutoTimer = null
        selView?.visibility = View.GONE; selVisible = false
    }

    // ====== Recognition ======

    @Volatile
    private var capturedBitmap: Bitmap? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null
    private var isCapturing = false
    private var captureSetupDone = false

    @Volatile private var isMonitoring = false
    @Volatile private var lastFrameHash: Long = 0
    private var monitorRunnable: Runnable? = null
    private var lastAutoRecognizeTime: Long = 0
    private var lastChangeTime: Long = 0
    private var lastSetupError: String? = null
    private var pendingFrameHash: Long = 0
    private var stableFrameCount = 0

    // 可配置参数（通过 Flutter 设置页同步）
    private var ballSizeDp: Int = 50       // 悬浮球直径（dp）
    private var borderWidthDp: Float = 3f  // 选区边框粗细（dp）
    private var defaultLockPanel: Boolean = false

    /// 从 FlutterSharedPreferences 读取已保存的设置，服务重启后保持用户配置
    private fun loadPersistedSettings() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val ball = prefs.getFloat("flutter.setting_ball_size", -1f)
            if (ball > 0f) ballSizeDp = ball.toInt().coerceIn(5, 80)
            val border = prefs.getFloat("flutter.setting_border_width", -1f)
            if (border > 0f) borderWidthDp = border.coerceIn(1f, 10f)
            defaultLockPanel = prefs.getBoolean("flutter.setting_default_lock", false)
            diag("load-settings", "ball=$ballSizeDp border=$borderWidthDp lock=$defaultLockPanel")
        } catch (e: Exception) {
            diag("load-settings", "failed, use defaults", e)
        }
    }

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.w(TAG, "MediaProjection onStop")
            diag("projection-stop", "captureSetup=$captureSetupDone inFlight=$recognitionInFlight")
            captureSetupDone = false
            mediaProjection = null
        }
    }

    private fun setupCapture() {
        if (captureSetupDone || mediaProjection == null) return

        val dm = DisplayMetrics()
        wm?.defaultDisplay?.getRealMetrics(dm)
        val captureW = dm.widthPixels
        val captureH = dm.heightPixels
        val captureDpi = dm.densityDpi
        screenW = captureW; screenH = captureH

        captureThread = HandlerThread("capture").also { it.start() }
        captureHandler = Handler(captureThread!!.looper)

        try {
            try { mediaProjection!!.unregisterCallback(projectionCallback) } catch (_: Exception) {}
            mediaProjection!!.registerCallback(projectionCallback, handler)

            imageReader = ImageReader.newInstance(captureW, captureH, PixelFormat.RGBA_8888, 2)
            imageReader!!.setOnImageAvailableListener(
                ImageReader.OnImageAvailableListener { reader ->
                    val img = reader.acquireLatestImage()
                    if (img != null) {
                        try {
                            if (isCapturing && capturedBitmap == null) {
                                capturedBitmap = imageToBitmap(img)
                            } else if (isMonitoring) {
                                val newHash = computeFrameHash(img)
                                val now = System.currentTimeMillis()
                                if (newHash != pendingFrameHash) {
                                    pendingFrameHash = newHash
                                    stableFrameCount = 0
                                    lastChangeTime = now
                                } else if (pendingFrameHash != 0L) {
                                    stableFrameCount++
                                    if (lastFrameHash != pendingFrameHash &&
                                        stableFrameCount >= 2 &&
                                        now - lastChangeTime >= 250 &&
                                        now - lastAutoRecognizeTime >= 900
                                    ) {
                                        lastFrameHash = pendingFrameHash
                                        lastAutoRecognizeTime = now
                                        lastChangeTime = 0
                                        stableFrameCount = 0
                                        isMonitoring = false
                                        handler.post { performRecognition(autoRecognize = true) }
                                    }
                                }
                            }
                    } catch (e: Exception) {
                        Log.e(TAG, "onImageAvailable error", e)
                        diag("image-reader", "frame processing failed capturing=$isCapturing monitoring=$isMonitoring", e)
                    } finally {

                            img.close()
                        }
                    }
                },
                captureHandler
            )

            virtualDisplay = mediaProjection!!.createVirtualDisplay(
                "capture", captureW, captureH, captureDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, imageReader!!.surface, null, captureHandler
            )
            captureSetupDone = true
        } catch (e: Exception) {
            Log.e(TAG, "setupCapture error", e)
            lastSetupError = e.message
            cleanupCaptureResources()
            // 瞬态失败较常见，1 秒后异步重试一次
            handler.postDelayed({
                if (!captureSetupDone && mediaProjection != null) {
                    setupCapture()
                }
            }, 1000)
        }
    }

    private fun performRecognition(autoRecognize: Boolean = false) {
        diag("recognition-start", "auto=$autoRecognize generation=${recognitionGeneration + 1} setup=$captureSetupDone")
        hideSel()
        stopMonitoring()
        if (mediaProjection == null) {
            updateAnswer("请先授权截图权限")
            return
        }
        if (recognitionInFlight) {
            if (!autoRecognize) updateAnswer("正在识别中，请稍候...")
            else startMonitoring()
            return
        }

        if (!captureSetupDone) {
            setupCapture()
            if (!captureSetupDone) {
                // 首次失败不提示，静默等待 setupCapture() 内部的异步重试（1s 后执行）
                handler.postDelayed({
                    if (captureSetupDone) {
                        performRecognition(autoRecognize)
                    } else {
                        val errMsg = lastSetupError ?: "未知错误"
                        Log.e(TAG, "performRecognition: setupCapture failed permanently: $errMsg")
                        if (!autoRecognize) updateAnswer("截图初始化失败：$errMsg")
                        else startMonitoring()
                    }
                }, 1500)
                return
            }
        }

        val generation = ++recognitionGeneration
        activeRecognitionGeneration = generation
        recognitionInFlight = true
        isCapturing = true
        capturedBitmap?.let { if (!it.isRecycled) it.recycle() }
        capturedBitmap = null

        recognitionTimeout?.let { handler.removeCallbacks(it) }
        recognitionTimeout = Runnable {
            if (recognitionInFlight && activeRecognitionGeneration == generation) {
                Log.w(TAG, "recognition timeout generation=$generation")
                diag("recognition-timeout", "generation=$generation auto=$autoRecognize")
                recognitionInFlight = false
                isCapturing = false
                if (autoRecognize) startMonitoring()
            }
        }
        handler.postDelayed(recognitionTimeout!!, 6000)

        val dm = DisplayMetrics()
        wm?.defaultDisplay?.getRealMetrics(dm)
        screenW = dm.widthPixels; screenH = dm.heightPixels

        if (!autoRecognize) {
            updateAnswer("识别中...")
        }
        // 自动识别时不改变面板文字，避免闪烁，仅后台处理

        waitForCaptureAndOcr(0, autoRecognize, generation)
    }

    private fun waitForCaptureAndOcr(
        retry: Int,
        autoRecognize: Boolean = false,
        generation: Long = activeRecognitionGeneration
    ) {
        handler.postDelayed({
            if (generation != activeRecognitionGeneration || !recognitionInFlight) return@postDelayed
            val bmp = capturedBitmap
            if (bmp != null) {
                capturedBitmap = null
                var cropped: Bitmap? = null
                try {
                    // 使用 bitmap 实际尺寸作为基准计算缩放比，避免 screenW/screenH 与 ImageReader 不一致
                    val sw = bmp.width.toFloat(); val sh = bmp.height.toFloat()
                    val scaleX = sw / screenW.coerceAtLeast(1)
                    val scaleY = sh / screenH.coerceAtLeast(1)
                    val cx = (selX * scaleX).toInt().coerceIn(0, bmp.width)
                    val cy = (selY * scaleY).toInt().coerceIn(0, bmp.height)
                    val cw = (selW * scaleX).toInt().coerceAtMost(bmp.width - cx)
                    val ch = (selH * scaleY).toInt().coerceAtMost(bmp.height - cy)
                    // 内缩 3px，避免选框边框像素被 OCR 误识别
                    val inset = (3 * resources.displayMetrics.density).toInt().coerceAtLeast(2)
                    val ix = (cx + inset).coerceIn(0, bmp.width - 1)
                    val iy = (cy + inset).coerceIn(0, bmp.height - 1)
                    val iw = (cw - inset * 2).coerceAtLeast(1)
                    val ih = (ch - inset * 2).coerceAtLeast(1)
                    cropped = if (iw > 0 && ih > 0)
                        Bitmap.createBitmap(bmp, ix, iy, iw, ih)
                    else bmp
                    if (cropped !== bmp) bmp.recycle()
                    isCapturing = false
                    ocr(cropped, autoRecognize, generation)
                } catch (e: Exception) {
                    Log.e(TAG, "waitForCapture crop error", e)
                    if (cropped != null && cropped !== bmp && !cropped!!.isRecycled) cropped!!.recycle()
                    if (!bmp.isRecycled) bmp.recycle()
                    finishRecognition(generation, autoRecognize)
                    if (!autoRecognize) updateAnswer("截图失败: ${e.message}")
                }
            } else if (retry < 5) {
                waitForCaptureAndOcr(retry + 1, autoRecognize, generation)
            } else {
                finishRecognition(generation, autoRecognize)
                if (!autoRecognize) updateAnswer("截图失败：未收到屏幕画面（请重试）")
            }
        }, 300)
    }

    private fun startMonitoring() {
        if (!captureSetupDone || !ansVisible) return
        stopMonitoring()
        pendingFrameHash = 0
        stableFrameCount = 0
        lastAutoRecognizeTime = System.currentTimeMillis()
        lastChangeTime = 0
        monitorRunnable = object : Runnable {
            override fun run() {
                if (ansVisible && !recognitionInFlight && !isCapturing && !isMonitoring) {
                    isMonitoring = true
                }
                handler.postDelayed(this, 300) // 300ms 轮询快速响应用户滑动切题
            }
        }
        handler.postDelayed(monitorRunnable!!, 500) // 500ms 首次启动延迟
    }

    private fun stopMonitoring() {
        monitorRunnable?.let { handler.removeCallbacks(it) }
        monitorRunnable = null
        isMonitoring = false
        pendingFrameHash = 0
        stableFrameCount = 0
    }

    private fun computeFrameHash(img: Image): Long {
        val planes = img.planes
        val buffer = planes[0].buffer
        val pixelStride = planes[0].pixelStride
        val rowStride = planes[0].rowStride
        val w = img.width; val h = img.height
        val sx = (selX * w / screenW).coerceIn(0, w - 1)
        val sy = (selY * h / screenH).coerceIn(0, h - 1)
        val ex = ((selX + selW) * w / screenW).coerceIn(0, w - 1)
        val ey = ((selY + selH) * h / screenH).coerceIn(0, h - 1)
        var hash = 0L
        for (i in 0..2) {
            for (j in 0..2) {
                val x = sx + (ex - sx) * i / 2
                val y = sy + (ey - sy) * j / 2
                val offset = y * rowStride + x * pixelStride
                if (offset + 2 < buffer.capacity()) {
                    hash = hash * 31 + (buffer.get(offset).toInt() and 0xFF)
                    hash = hash * 31 + (buffer.get(offset + 1).toInt() and 0xFF)
                    hash = hash * 31 + (buffer.get(offset + 2).toInt() and 0xFF)
                }
            }
        }
        return hash
    }

    private fun cleanupCaptureResources() {
        diag("capture-cleanup", "setup=$captureSetupDone reader=${imageReader != null} display=${virtualDisplay != null}")
        try { virtualDisplay?.release() } catch (error: Exception) { diag("capture-cleanup-display", "release failed", error) }
        try { imageReader?.close() } catch (_: Exception) {}
        try { captureThread?.quitSafely() } catch (_: Exception) {}
        imageReader = null; virtualDisplay = null
        capturedBitmap?.let { if (!it.isRecycled) it.recycle() }
        capturedBitmap = null
        recognitionTimeout?.let { handler.removeCallbacks(it) }
        recognitionTimeout = null
        recognitionInFlight = false
        captureThread = null; captureHandler = null
        captureSetupDone = false
    }

    private fun cleanupCapture() {
        cleanupCaptureResources()
        try { mediaProjection?.unregisterCallback(projectionCallback) } catch (_: Exception) {}
        isCapturing = false
    }

    private fun imageToBitmap(img: Image): Bitmap {
        val planes = img.planes
        val buffer = planes[0].buffer
        val pixelStride = planes[0].pixelStride
        val rowStride = planes[0].rowStride
        val rowPadding = rowStride - pixelStride * img.width
        buffer.rewind()
        return if (rowPadding == 0) {
            val bmp = Bitmap.createBitmap(img.width, img.height, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(buffer)
            bmp
        } else {
            val bmpWidth = img.width + rowPadding / pixelStride
            val padded = Bitmap.createBitmap(bmpWidth, img.height, Bitmap.Config.ARGB_8888)
            padded.copyPixelsFromBuffer(buffer)
            val result = Bitmap.createBitmap(padded, 0, 0, img.width, img.height)
            padded.recycle()
            result
        }
    }

    /// 从 OCR 原始文本中提取题目正文（仅题干，不含选项）。
    /// 策略：按行分割 → 过滤 UI 噪声行 → 取选项前的连续中文行作为题干。
    /// 之前版本会把选项内容混入题干导致"乱码"，现在仅提取第一个选项前的纯题干。
    private fun extractQuestionText(ocrText: String): String {
        if (ocrText.isBlank()) return ocrText

        // UI 噪声模式（考试页面元素）：倒计时、时间戳、交卷、题型标签、翻页、分数、进度等
        val noisePatterns = listOf(
            Regex("""[0O]?\s*倒计时[\s　]*\d{1,2}[.:：]\d{2}(?:[.:：]\d{2})?"""),
            Regex("""[\(（【]?\s*交卷\s*[\)）】]?"""),
            Regex("""\b\d{1,2}[:：]\d{2}[:：]\d{2}\b"""),
            Regex("""^\s*选\s*[,，]?\s*$"""),
            Regex("""^\s*[A-D]\s*(?=[A-D]\s*[A-D])"""), // "A B C D" 连续选项
            Regex("""^\s*\d+\s*$"""),                     // 纯数字行
            Regex("""(单选题|多选题|判断题|填空题|简答题|选择题|答题卡|剩余时间|上一题|下一题|上一页|下一页|收藏|笔记|举报|分享|未作答|请选择|正确答案|你的答案)"""),
            Regex("""^\s*(得分|总分|成绩|进度)[\s:：]*\d*\s*%?"""),
            Regex("""^\s*第\s*\d+\s*[/\/]\s*\d+\s*题?"""),
            Regex("""^\s*第\s*\d+\s*页"""),
            Regex("""^\s*\d+\s*%"""),
            // 新增：考试小程序 UI 噪声
            Regex("""^\s*\d+\s*[/\/⼀]\s*\d+\s*$"""),   // "4/100" 进度
            Regex("""^\s*\d{1,2}\s*[:：]\s*\d{2}\s*$"""), // "00:00" 倒计时（独立行）
            Regex("""^\s*备注栏\s*.*$"""),               // 答案面板溢出
            Regex("""^\s*选项\b"""),                     // "选项A/B/C/D" 前缀
            Regex("""^\s*单\s*项\s*选\s*择\s*题\s*$"""), // 变体标签
            Regex("""^\s*多\s*项\s*选\s*择\s*题\s*$"""), // 变体标签
            Regex("""^\s*判\s*断\s*题\s*$"""),           // 变体标签
            Regex("""(多项选择题|单项选择题)"""),         // 不加空格的标签
            Regex("""^\s*第\s*\d+\s*题\s*$"""),          // "第4题"
            // OCR 题型标签乱码变体："多选题"→"2斩题 多造"、"多选题"→"多逸" 等
            Regex("""斩\s*题"""),                            // "斩题"（"多选题"→"2斩题/&斩题" 乱码，无条件删除）
            Regex("""多造"""),                              // "多选" 误识别
            Regex("""多逸"""),                              // "多选" 误识别（变体）
            Regex("""^\s*多\s*选\s*"""),                 // 行首独立"多选"题型标签
            Regex("""^服漫食丁旨力"""),                    // 特定考试App UI 乱码
            Regex("""^漫食丁旨力"""),                      // 乱码变体（少1字）
        )

        // 选项行锚点：A./B、/C．/(D) 等
        val optionPrefix = Regex("""^\s*[\(（]?[A-H][\)）\.、．]\s*""")

        val lines = ocrText.split("\n").map { it.trim() }
        val cleaned = mutableListOf<String>()   // 清洗后的文本行
        var firstOptionIdx = -1                  // 第一个选项所在行索引

        for (rawLine in ocrText.split("\n")) {
            var s = rawLine.trim()
            if (s.isEmpty()) { cleaned.add(""); continue }
            for (p in noisePatterns) s = p.replace(s, "")
            s = s.trim()
            if (s.length < 2) { cleaned.add(""); continue }
            // 题干/选项以中文为主；纯字母数字行（非选项）丢弃
            val chinese = s.count { it in '\u4e00'..'\u9fff' }
            if (chinese < 2 && !optionPrefix.containsMatchIn(s)) { cleaned.add(""); continue }
            // 检测首个选项锚点
            if (optionPrefix.containsMatchIn(s) && firstOptionIdx < 0) {
                firstOptionIdx = cleaned.size
            }
            cleaned.add(s)
        }

        // 策略 A：存在选项锚点 → 提取题干 + 选项内容（去掉选项前缀）
        if (firstOptionIdx >= 0 && firstOptionIdx < cleaned.size) {
            val stemLines = mutableListOf<String>()
            for (j in 0 until firstOptionIdx) {
                if (cleaned[j].isNotEmpty()) stemLines.add(cleaned[j])
            }
            // 收集选项行，去掉选项前缀（如 "A. "、"B. " 等）
            val optionLines = mutableListOf<String>()
            for (j in firstOptionIdx until cleaned.size) {
                val line = cleaned[j]
                if (line.isNotEmpty()) {
                    val stripped = optionPrefix.replaceFirst(line, "").trim()
                    if (stripped.isNotEmpty()) optionLines.add(stripped)
                }
            }
            if (stemLines.isNotEmpty()) {
                val result = if (optionLines.isNotEmpty()) {
                    stemLines.joinToString(" ") + " " + optionLines.joinToString(" ")
                } else {
                    stemLines.joinToString(" ")
                }
                return result
            }
        }

        // 策略 B（回退）：保留所有清洗后非空行
        val fallback = cleaned.filter { it.isNotEmpty() }.joinToString(" ")
        if (fallback.isNotEmpty()) {
            return fallback
        }
        return ocrText
    }

    /// 从 OCR 原始文本检测题型
    private fun detectQuestionType(ocrText: String): String {
        val normalized = ocrText
            .replace(Regex("[\\s　·•|丨]"), "")
            .replace("选择题", "选择题")

        // 页面题型标签优先，兼容 OCR 只识别出“单选/多选/判断”的情况。
        if (normalized.contains("多选") || normalized.contains("可多选") ||
            normalized.contains("多项选择") || normalized.contains("多项选择题") ||
            normalized.contains("多造") || normalized.contains("多逸")) {
            return "multi"
        }
        if (normalized.contains("单选") || normalized.contains("单项选择") ||
            normalized.contains("单项选择题")) {
            return "single"
        }
        if (normalized.contains("判断题") || normalized.contains("判断")) {
            return "judge"
        }

        val lines = ocrText.split("\n").map { it.trim() }
        val optionPrefix = Regex("""^\s*[\(（]?[A-H][\)\.、．:]\s*""")
        val optionTexts = lines
            .filter { optionPrefix.containsMatchIn(it) }
            .map { optionPrefix.replaceFirst(it, "").trim() }
            .filter { it.isNotEmpty() }
        val judgeWords = setOf("正确", "错误", "对", "错", "是", "否")

        // 只有所有有效选项都是完整判断词时，才认定为判断题。
        if (optionTexts.size >= 2 && optionTexts.all { it in judgeWords }) {
            return "judge"
        }
        // 没有明确标签时，两个及以上普通选项按单选处理，避免误判为判断题。
        if (optionTexts.size >= 2) return "single"
        return ""
    }

    private fun finishRecognition(generation: Long, autoRecognize: Boolean) {
        diag("recognition-finish", "generation=$generation active=$activeRecognitionGeneration auto=$autoRecognize")
        if (generation != activeRecognitionGeneration) return
        recognitionInFlight = false
        isCapturing = false
        recognitionTimeout?.let { handler.removeCallbacks(it) }
        recognitionTimeout = null
        if (autoRecognize) startMonitoring()
    }

    private fun ocr(bitmap: Bitmap, autoRecognize: Boolean = false, generation: Long = activeRecognitionGeneration) {
        textRecognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { t ->
                if (generation != activeRecognitionGeneration) {
                    if (!bitmap.isRecycled) bitmap.recycle()
                    return@addOnSuccessListener
                }
                val rawText = t.text.trim()
                if (rawText.isEmpty()) {
                    if (!autoRecognize) updateAnswer("未检测到文字")
                    finishRecognition(generation, autoRecognize)
                } else {
                    // 从原始 OCR 文本检测题型
                    val ocrType = detectQuestionType(rawText)
                    // 提取题目正文（仅题干，去掉 UI 噪声和选项内容）
                    val questionText = extractQuestionText(rawText)
                    diag("ocr-text", "raw=[$rawText] type=$ocrType")
                    diag("ocr-extracted", "question=[$questionText]")
                    // 提取后文本太短不进行匹配，避免"乱码"误匹配
                    val chineseChars = questionText.count { it in '\u4e00'..'\u9fff' }
                    if (questionText.isBlank() || chineseChars < 3) {
                        updateAnswer("未检测到有效题目，请调整题区并重试")
                        finishRecognition(generation, autoRecognize)
                    } else {
                        matchAndShow(questionText, ocrType, generation)
                    }
                }
                if (!bitmap.isRecycled) bitmap.recycle()
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "ocr: failed", e)
                diag("ocr-failed", "generation=$generation auto=$autoRecognize", e)
                if (!autoRecognize) updateAnswer("OCR 失败: ${e.message}")
                finishRecognition(generation, autoRecognize)
                if (!bitmap.isRecycled) bitmap.recycle()
            }
    }

    private fun matchAndShow(
        ocrText: String,
        ocrType: String = "",
        generation: Long = activeRecognitionGeneration,
        autoRecognize: Boolean = false
    ) {
        if (generation != activeRecognitionGeneration) return
        diag("match-send", "text=[$ocrText] type=$ocrType gen=$generation")
        val args = mapOf("text" to ocrText, "type" to ocrType, "generation" to generation)
        // 通道为空时先尝试重建，再取值
        val ch = recognitionChannel ?: run {
            setupRecognitionChannel()
            recognitionChannel
        }
        if (ch != null) {
            try {
                pendingAutoQuestionSignature = if (autoRecognize) normalizeQuestionSignature(ocrText) else null
                pendingForceRefresh = !autoRecognize
                ch.invokeMethod("recognize", args)
                if (!autoRecognize && !ansContent.startsWith("识别中")) {
                    handler.post {
                        ansContent = "匹配中..."
                        refreshAnswerPanel()
                    }
                }
                recognitionTimeout?.let { handler.removeCallbacks(it) }
                recognitionTimeout = Runnable {
                    if (generation == activeRecognitionGeneration && recognitionInFlight) {
                        ansContent = "识别超时，请重试或调整题区"
                        refreshAnswerPanel()
                        finishRecognition(generation, autoRecognize = true)
                    }
                }
                handler.postDelayed(recognitionTimeout!!, 5000)
                return
            } catch (e: Exception) {
                Log.e(TAG, "matchAndShow: invoke recognize failed", e)
            }
        }
        ansContent = "识别结果\n\n$ocrText"
        refreshAnswerPanel()
    }

    private fun formatResult(
        text: String,
        answer: String,
        explanation: String,
        level: String,
        cands: List<Candidate>,
        candIdx: Int,
        fromCandidate: Boolean = false
    ): String {
        val sb = StringBuilder()
        if (level == "none" || answer.isEmpty()) {
            if (cands.isNotEmpty()) {
                val c = cands[candIdx]
                sb.append("【未精确匹配，显示第 ${candIdx + 1}/${cands.size} 个候选】\n\n")
                sb.append(c.question).append("\n\n")
                sb.append("\u2713 答案：").append(c.answer)
                if (c.explanation.isNotEmpty()) {
                    sb.append("\n\n\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n")
                    sb.append("解析：\n").append(c.explanation)
                }
            } else {
                sb.append("【未匹配到题库】\n\n")
                sb.append("识别内容：\n").append(text)
            }
        } else {
            sb.append(text).append("\n\n")
            sb.append("\u2713 正确答案：").append(formatAnswerForDisplay(answer))
            if (explanation.isNotEmpty()) {
                sb.append("\n\n\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\n")
                sb.append("解析：\n").append(explanation)
            }
            if (!fromCandidate) {
                sb.append("\n\n[").append(if (level == "exact") "精确" else "模糊").append("匹配]")
            }
        }
        return sb.toString()
    }

    private fun formatAnswerForDisplay(answer: String): String {
        val original = answer.trim()
        if (original.isEmpty()) return original

        val markerPattern = Regex("""(?<![A-Z])([A-D]{1,4})(?=\s|[.、．。:：)）]|$)""")
        val letters = linkedSetOf<Char>()
        markerPattern.findAll(original.uppercase()).forEach { match ->
            match.groupValues[1].forEach { letters.add(it) }
        }
        return if (letters.isEmpty()) original else letters.joinToString("")
    }

    private fun formatAnswerSummary(answer: String, level: String): String {
        if (level == "none" || answer.isBlank()) return "正确答案：--"
        return "正确答案：${formatAnswerForDisplay(answer)}"
    }

    private fun normalizeQuestionSignature(text: String): String {
        return text.uppercase()
            .replace(Regex("\\s+"), "")
            .replace(Regex("[，。！？、；：,.!?;:()（）\\[\\]【】]"), "")
            // 移除应用面板字符串，避免面板显示内容影响签名对比
            .replace(Regex("匹配中[.…]*|识别中[.…]*|识别超时.*|正确答案[:：]?.*|你的答案[:：]?.*"), "")
            .trim()
    }

    private fun updateAnswer(text: String) {
        ansContent = text
        handler.post { showAnswer() }
    }

    /// 从 Flutter 设置页同步参数，运行时立即生效
    fun applySettings(ballSize: Int, borderWidth: Float, defaultLock: Boolean) {
        val needRecreateBall = ballSize != ballSizeDp
        val needRedraw = borderWidth.toInt() != borderWidthDp.toInt()
        ballSizeDp = ballSize.coerceIn(5, 80)
        borderWidthDp = borderWidth.coerceIn(1f, 10f)
        defaultLockPanel = defaultLock
        if (needRecreateBall) handler.post { recreateBall() }
        if (needRedraw) handler.post { redrawBall(); redrawSelection() }
        diag("apply-settings", "ball=$ballSizeDp border=$borderWidthDp lock=$defaultLockPanel recreate=$needRecreateBall redraw=$needRedraw")
    }

    /// 销毁旧悬浮球并按新尺寸重建，保留当前位置
    private fun recreateBall() {
        val oldX = ballParams?.x ?: 50
        val oldY = ballParams?.y ?: 500
        try {
            ball?.let { wm?.removeView(it) }
        } catch (e: Exception) {
            diag("recreate-ball", "remove failed", e)
        }
        ball = null
        ballParams = null
        createBall(oldX, oldY)
        diag("recreate-ball", "done sizeDp=$ballSizeDp pos=($oldX,$oldY)")
    }

    /// 重绘悬浮球边框
    private fun redrawBall() {
        val v = ball ?: return
        val bg = v.background as? GradientDrawable ?: return
        bg.setStroke(borderWidthDp.toInt(), 0xFFFFFFFF.toInt())
        bg.invalidateSelf()
        v.invalidate()
        diag("redraw-ball", "stroke=${borderWidthDp.toInt()}")
    }

    /// 重绘选区边框
    private fun redrawSelection() {
        val v = selView ?: return
        val bg = v.background as? GradientDrawable ?: return
        bg.setStroke(borderWidthDp.toInt(), 0xFF888888.toInt())
        bg.invalidateSelf()
        v.invalidate()
        diag("redraw-selection", "stroke=${borderWidthDp.toInt()}")
    }

    data class Candidate(val question: String, val answer: String, val explanation: String, val score: Double)
}

// android/app/src/main/kotlin/com/sightmate/blindassist/MainActivity.kt
// MODULE 4 – Native Android Platform Channel Hub
//
// Registers ALL native MethodChannels and EventChannels for SightMate:
//   1. sightmate/hardware_switches  — EventChannel for volume key interception
//   2. sightmate/blind_mode         — MethodChannel to toggle key capture mode
//   3. sightmate/optical_flow       — MethodChannel for OpenCV Lucas-Kanade
//   4. sightmate/paddle_ocr         — MethodChannel for PaddleOCR ONNX Runtime
//   5. sightmate/audio              — MethodChannel for confirmation beep tones
//
// Volume key interception:
//   • onKeyDown override captures KEYCODE_VOLUME_UP / KEYCODE_VOLUME_DOWN
//   • Events consumed (returns true) ONLY when blindModeActive = true
//   • This prevents the system volume overlay from appearing
//   • Raw key identity ('UP' / 'DOWN') broadcast via EventChannel sink

package com.sightmate.blindassist

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "SightMate"

        // Channel names — must match Dart-side constants exactly
        const val CH_SWITCHES    = "sightmate/hardware_switches"
        const val CH_BLIND_MODE  = "sightmate/blind_mode"
        const val CH_OPT_FLOW    = "sightmate/optical_flow"
        const val CH_PADDLE_OCR  = "sightmate/paddle_ocr"
        const val CH_AUDIO       = "sightmate/audio"
    }

    // ── State ─────────────────────────────────────────────────────────────────
    @Volatile private var blindModeActive: Boolean = false
    private var switchEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Audio: ToneGenerator for confirmation beeps ───────────────────────────
    private val toneGenerator: ToneGenerator by lazy {
        ToneGenerator(AudioManager.STREAM_MUSIC, 40)
    }

    // ── FlutterEngine configuration ───────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        registerSwitchChannel(flutterEngine)
        registerBlindModeChannel(flutterEngine)
        registerOpticalFlowChannel(flutterEngine)
        registerPaddleOCRChannel(flutterEngine)
        registerAudioChannel(flutterEngine)

        Log.i(TAG, "All platform channels registered.")
    }

    // ────────────────────────────────────────────────────────────────────────
    // 1. Hardware Switches – EventChannel
    // ────────────────────────────────────────────────────────────────────────

    private fun registerSwitchChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, CH_SWITCHES)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    switchEventSink = events
                    Log.d(TAG, "[$CH_SWITCHES] Listening")
                }
                override fun onCancel(arguments: Any?) {
                    switchEventSink = null
                    Log.d(TAG, "[$CH_SWITCHES] Cancelled")
                }
            })
    }

    // ────────────────────────────────────────────────────────────────────────
    // 2. Blind Mode – MethodChannel
    // ────────────────────────────────────────────────────────────────────────

    private fun registerBlindModeChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_BLIND_MODE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBlindMode" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        blindModeActive = active
                        Log.i(TAG, "Blind mode: $active")
                        result.success(null)
                    }
                    "isBlindMode" -> result.success(blindModeActive)
                    else -> result.notImplemented()
                }
            }
    }

    // ────────────────────────────────────────────────────────────────────────
    // 3. Volume Key Interception (onKeyDown override)
    // ────────────────────────────────────────────────────────────────────────

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!blindModeActive) {
            return super.onKeyDown(keyCode, event)
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                broadcastSwitch("UP")
                true  // Consume event — prevents system volume overlay
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                broadcastSwitch("DOWN")
                true  // Consume event
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        // Also consume key-up for volume keys in blind mode
        if (blindModeActive && (keyCode == KeyEvent.KEYCODE_VOLUME_UP
                || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun broadcastSwitch(identity: String) {
        mainHandler.post {
            switchEventSink?.success(identity)
            Log.v(TAG, "Switch: $identity")
        }
    }

    // ────────────────────────────────────────────────────────────────────────
    // 4. Optical Flow – MethodChannel (wraps C++ OpenCV native library)
    // ────────────────────────────────────────────────────────────────────────

    private fun registerOpticalFlowChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_OPT_FLOW)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "computeOpticalFlow" -> {
                        val prevY  = call.argument<ByteArray>("prevY")
                        val currY  = call.argument<ByteArray>("currY")
                        val width  = call.argument<Int>("width")  ?: 0
                        val height = call.argument<Int>("height") ?: 0

                        if (prevY == null || currY == null || width == 0 || height == 0) {
                            result.success(mapOf(
                                "dx" to 0.0, "dy" to 0.0,
                                "rotation" to 0.0, "scale" to 1.0,
                                "reliable" to false
                            ))
                            return@setMethodCallHandler
                        }

                        // Run OpenCV computation on a background thread
                        Thread {
                            try {
                                val egoMotion = computeOpticalFlowNative(
                                    prevY, currY, width, height
                                )
                                mainHandler.post { result.success(egoMotion) }
                            } catch (e: UnsatisfiedLinkError) {
                                // Native library not linked (debug without NDK)
                                mainHandler.post {
                                    result.success(mapOf(
                                        "dx" to 0.0, "dy" to 0.0,
                                        "rotation" to 0.0, "scale" to 1.0,
                                        "reliable" to false
                                    ))
                                }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("OPTICAL_FLOW_ERROR", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Native method declaration — implemented in optical_flow_wrapper.cpp
    private external fun computeOpticalFlowNative(
        prevY: ByteArray,
        currY: ByteArray,
        width: Int,
        height: Int,
    ): Map<String, Any>

    // ────────────────────────────────────────────────────────────────────────
    // 5. PaddleOCR – MethodChannel (ONNX Runtime + MLKit fallback)
    // ────────────────────────────────────────────────────────────────────────

    private var paddleOcrHelper: PaddleOcrHelper? = null

    private fun registerPaddleOCRChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_PADDLE_OCR)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        val detModel = call.argument<String>("detModelAsset") ?: ""
                        val recModel = call.argument<String>("recModelAsset") ?: ""
                        val useNNAPI = call.argument<Boolean>("useNNAPI") ?: true
                        val threads  = call.argument<Int>("numThreads") ?: 4

                        Thread {
                            try {
                                paddleOcrHelper = PaddleOcrHelper(
                                    context      = applicationContext,
                                    detModelPath = detModel,
                                    recModelPath = recModel,
                                    useNNAPI     = useNNAPI,
                                    numThreads   = threads
                                )
                                val ok = paddleOcrHelper!!.initialize()
                                mainHandler.post { result.success(ok) }
                            } catch (e: Exception) {
                                Log.w(TAG, "PaddleOCR init failed: ${e.message}")
                                mainHandler.post { result.success(false) }
                            }
                        }.start()
                    }

                    "recognize" -> {
                        val imageBytes = call.argument<ByteArray>("imageBytes")
                        if (imageBytes == null || paddleOcrHelper == null) {
                            result.success(mapOf("regions" to emptyList<Any>()))
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                val ocrResult = paddleOcrHelper!!.recognize(imageBytes)
                                mainHandler.post { result.success(ocrResult) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("OCR_ERROR", e.message, null) }
                            }
                        }.start()
                    }

                    "recognizeFallback" -> {
                        // MLKit fallback — synchronous enough for background thread
                        val imageBytes = call.argument<ByteArray>("imageBytes")
                        if (imageBytes == null) {
                            result.success("")
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val text = MLKitOcrHelper.recognizeBytes(applicationContext, imageBytes)
                                mainHandler.post { result.success(text) }
                            } catch (e: Exception) {
                                mainHandler.post { result.success("") }
                            }
                        }.start()
                    }

                    "dispose" -> {
                        paddleOcrHelper?.close()
                        paddleOcrHelper = null
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ────────────────────────────────────────────────────────────────────────
    // 6. Audio Channel – Confirmation Beep
    // ────────────────────────────────────────────────────────────────────────

    private fun registerAudioChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_AUDIO)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playBeep" -> {
                        val durationMs = call.argument<Int>("durationMs") ?: 60
                        // ToneGenerator plays TONE_PROP_BEEP — short distinct click
                        toneGenerator.startTone(ToneGenerator.TONE_PROP_BEEP, durationMs)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ────────────────────────────────────────────────────────────────────────
    // Cleanup
    // ────────────────────────────────────────────────────────────────────────

    override fun onDestroy() {
        super.onDestroy()
        paddleOcrHelper?.close()
        toneGenerator.release()
        blindModeActive = false
    }

    // ── NDK shared library loader ─────────────────────────────────────────────
    init {
        try {
            System.loadLibrary("sightmate_cv")
            Log.i(TAG, "OpenCV native library loaded.")
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "OpenCV native library not found — optical flow disabled.")
        }
    }
}

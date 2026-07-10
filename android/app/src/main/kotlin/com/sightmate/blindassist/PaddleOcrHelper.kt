// android/app/src/main/kotlin/com/sightmate/blindassist/PaddleOcrHelper.kt
// MODULE 2 – PaddleOCR ONNX Runtime Helper (Android Native)
//
// Implements the two-stage PaddleOCR v4 pipeline:
//   Stage 1: DBNet text detection (ch_PP-OCRv4_det_infer.onnx)
//     - Produces a probability map → threshold → contour detection → bounding boxes
//   Stage 2: CRNN text recognition (ch_PP-OCRv4_rec_infer.onnx)
//     - Each detected crop → CRNN → CTC greedy decode → character string
//
// NNAPI execution provider is requested first; falls back to CPU if unavailable.
// Both sessions are created once at initialization and reused across calls.
//
// DEPENDENCY: onnxruntime-android must be added to build.gradle.kts

package com.sightmate.blindassist

import ai.onnxruntime.*
import android.content.Context
import android.graphics.*
import android.util.Log
import java.io.ByteArrayOutputStream
import java.nio.FloatBuffer
import kotlin.math.*

class PaddleOcrHelper(
    private val context:      Context,
    private val detModelPath: String,
    private val recModelPath: String,
    private val useNNAPI:     Boolean = true,
    private val numThreads:   Int     = 4,
) {
    companion object {
        private const val TAG = "PaddleOCR"

        // Detection model constants
        private const val DET_INPUT_SIZE = 640     // Multiple of 32
        private const val DET_THRESHOLD  = 0.3f
        private const val DET_BOX_THRESH = 0.5f
        private const val DET_UNCLIP     = 1.5f   // Box expansion ratio

        // Recognition model constants
        private const val REC_HEIGHT     = 48
        private const val REC_MAX_WIDTH  = 320

        // CRNN character set (simplified Latin — replace with full dict for production)
        private val CHAR_SET = " !\"#\$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
                "[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    }

    private var env:         OrtEnvironment? = null
    private var detSession:  OrtSession?     = null
    private var recSession:  OrtSession?     = null
    private var initialized: Boolean         = false

    // ── Initialize ONNX sessions ──────────────────────────────────────────────

    fun initialize(): Boolean {
        return try {
            env = OrtEnvironment.getEnvironment()

            val sessionOpts = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(numThreads)
                setInterOpNumThreads(2)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)

                if (useNNAPI) {
                    try {
                        addNnapi()
                        Log.i(TAG, "NNAPI execution provider enabled.")
                    } catch (e: OrtException) {
                        Log.w(TAG, "NNAPI unavailable: ${e.message}. Using CPU.")
                    }
                }
            }

            // Load model bytes from assets
            val detBytes = loadAssetBytes(detModelPath)
            val recBytes = loadAssetBytes(recModelPath)

            if (detBytes == null || recBytes == null) {
                Log.e(TAG, "Model assets not found: $detModelPath / $recModelPath")
                return false
            }

            detSession = env!!.createSession(detBytes, sessionOpts)
            recSession = env!!.createSession(recBytes, sessionOpts)

            initialized = true
            Log.i(TAG, "PaddleOCR sessions initialized successfully.")
            true
        } catch (e: Exception) {
            Log.e(TAG, "PaddleOCR initialization failed: ${e.message}")
            false
        }
    }

    // ── Main pipeline: JPEG bytes → OCR result map ────────────────────────────

    fun recognize(jpegBytes: ByteArray): Map<String, Any> {
        if (!initialized || detSession == null || recSession == null) {
            return mapOf("regions" to emptyList<Map<String, Any>>())
        }

        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
            ?: return mapOf("regions" to emptyList<Map<String, Any>>())

        // Stage 1: Detect text regions
        val boxes = detectTextRegions(bitmap)
        if (boxes.isEmpty()) {
            bitmap.recycle()
            return mapOf("regions" to emptyList<Map<String, Any>>())
        }

        // Stage 2: Recognize text in each crop
        val regions = mutableListOf<Map<String, Any>>()
        for (box in boxes) {
            val crop   = cropRegion(bitmap, box) ?: continue
            val text   = recognizeText(crop)
            crop.recycle()

            if (text.isNotEmpty()) {
                regions.add(mapOf(
                    "polygon"    to box.toPolygonList(),
                    "text"       to text,
                    "confidence" to 0.85,
                ))
            }
        }

        bitmap.recycle()
        return mapOf("regions" to regions)
    }

    // ── Stage 1: DBNet text detection ────────────────────────────────────────

    private fun detectTextRegions(bitmap: Bitmap): List<TextBox> {
        val (scaledW, scaledH) = getScaledSize(bitmap.width, bitmap.height, DET_INPUT_SIZE)

        val scaled   = Bitmap.createScaledBitmap(bitmap, scaledW, scaledH, true)
        val inputTensor = bitmapToNormalizedTensor(scaled, scaledW, scaledH)
        scaled.recycle()

        val inputName = detSession!!.inputNames.iterator().next()
        val shape     = longArrayOf(1, 3, scaledH.toLong(), scaledW.toLong())
        val tensor    = OnnxTensor.createTensor(env, inputTensor, shape)

        val results   = detSession!!.run(mapOf(inputName to tensor))
        val probMap   = (results[0].value as Array<*>)[0] as Array<*>

        tensor.close()
        results.close()

        // Threshold probability map → find contours → bounding boxes
        return extractBoxes(probMap, scaledW, scaledH, bitmap.width, bitmap.height)
    }

    private fun getScaledSize(w: Int, h: Int, maxSize: Int): Pair<Int, Int> {
        val ratio = maxSize.toFloat() / max(w, h)
        var sw = (w * ratio).toInt()
        var sh = (h * ratio).toInt()
        // Round up to multiple of 32 (DBNet requirement)
        sw = ((sw + 31) / 32) * 32
        sh = ((sh + 31) / 32) * 32
        return Pair(sw.coerceAtMost(maxSize), sh.coerceAtMost(maxSize))
    }

    private fun bitmapToNormalizedTensor(bitmap: Bitmap, w: Int, h: Int): FloatBuffer {
        val buffer  = FloatBuffer.allocate(3 * w * h)
        val pixels  = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)

        // ImageNet normalization: mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
        val meanR = 0.485f; val stdR = 0.229f
        val meanG = 0.456f; val stdG = 0.224f
        val meanB = 0.406f; val stdB = 0.225f

        // Channel-first layout: [C, H, W]
        val rBuf = FloatArray(w * h)
        val gBuf = FloatArray(w * h)
        val bBuf = FloatArray(w * h)

        for (i in pixels.indices) {
            val pixel = pixels[i]
            rBuf[i] = ((Color.red(pixel)   / 255f) - meanR) / stdR
            gBuf[i] = ((Color.green(pixel) / 255f) - meanG) / stdG
            bBuf[i] = ((Color.blue(pixel)  / 255f) - meanB) / stdB
        }

        buffer.put(rBuf); buffer.put(gBuf); buffer.put(bBuf)
        buffer.rewind()
        return buffer
    }

    private fun extractBoxes(
        probMap: Array<*>,
        scaledW: Int, scaledH: Int,
        origW: Int,   origH:   Int,
    ): List<TextBox> {
        val boxes = mutableListOf<TextBox>()
        val mapH  = (probMap as Array<*>).size
        if (mapH == 0) return boxes
        val mapW  = ((probMap[0] as? FloatArray)?.size ?: (probMap[0] as? Array<*>)?.size) ?: 0

        val binary = Array(mapH) { y ->
            BooleanArray(mapW) { x ->
                val v = when (val row = probMap[y]) {
                    is FloatArray  -> row[x]
                    is Array<*>    -> (row[x] as? Float) ?: 0f
                    else           -> 0f
                }
                v > DET_THRESHOLD
            }
        }

        // Simple connected component → bounding rect extraction
        val visited = Array(mapH) { BooleanArray(mapW) }
        val scaleX  = origW.toFloat() / scaledW
        val scaleY  = origH.toFloat() / scaledH
        val mapScaleX = scaledW.toFloat() / mapW
        val mapScaleY = scaledH.toFloat() / mapH

        for (y in 0 until mapH) {
            for (x in 0 until mapW) {
                if (!binary[y][x] || visited[y][x]) continue
                val component = floodFill(binary, visited, x, y, mapW, mapH)
                if (component.size < 10) continue   // Skip tiny noise regions

                var minX = Int.MAX_VALUE; var minY = Int.MAX_VALUE
                var maxX = Int.MIN_VALUE; var maxY = Int.MIN_VALUE
                for ((cx, cy) in component) {
                    if (cx < minX) minX = cx; if (cy < minY) minY = cy
                    if (cx > maxX) maxX = cx; if (cy > maxY) maxY = cy
                }

                // Scale back to original image coordinates
                val ox1 = (minX * mapScaleX * scaleX).toInt().coerceIn(0, origW)
                val oy1 = (minY * mapScaleY * scaleY).toInt().coerceIn(0, origH)
                val ox2 = (maxX * mapScaleX * scaleX).toInt().coerceIn(0, origW)
                val oy2 = (maxY * mapScaleY * scaleY).toInt().coerceIn(0, origH)

                if (ox2 - ox1 > 5 && oy2 - oy1 > 2) {
                    boxes.add(TextBox(ox1, oy1, ox2, oy2))
                }
            }
        }

        return boxes
    }

    private fun floodFill(
        grid: Array<BooleanArray>, visited: Array<BooleanArray>,
        startX: Int, startY: Int, w: Int, h: Int,
    ): List<Pair<Int, Int>> {
        val result  = mutableListOf<Pair<Int, Int>>()
        val queue   = ArrayDeque<Pair<Int, Int>>()
        queue.add(startX to startY)
        visited[startY][startX] = true

        while (queue.isNotEmpty()) {
            val (cx, cy) = queue.removeFirst()
            result.add(cx to cy)
            for ((dx, dy) in listOf(0 to 1, 0 to -1, 1 to 0, -1 to 0)) {
                val nx = cx + dx; val ny = cy + dy
                if (nx in 0 until w && ny in 0 until h && !visited[ny][nx] && grid[ny][nx]) {
                    visited[ny][nx] = true
                    queue.add(nx to ny)
                }
            }
        }
        return result
    }

    // ── Stage 2: CRNN text recognition ───────────────────────────────────────

    private fun recognizeText(crop: Bitmap): String {
        val targetW = ((crop.width * REC_HEIGHT.toFloat() / crop.height)
            .toInt()).coerceIn(1, REC_MAX_WIDTH)

        val scaled = Bitmap.createScaledBitmap(crop, targetW, REC_HEIGHT, true)
        val inputTensor = bitmapToNormalizedTensor(scaled, targetW, REC_HEIGHT)
        scaled.recycle()

        val inputName = recSession!!.inputNames.iterator().next()
        val shape     = longArrayOf(1, 3, REC_HEIGHT.toLong(), targetW.toLong())
        val tensor    = OnnxTensor.createTensor(env, inputTensor, shape)

        return try {
            val results = recSession!!.run(mapOf(inputName to tensor))
            val logits  = results[0].value  // [1, T, num_chars]
            val text    = ctcGreedyDecode(logits)
            results.close()
            text
        } catch (e: Exception) {
            Log.w(TAG, "CRNN recognize error: ${e.message}")
            ""
        } finally {
            tensor.close()
        }
    }

    private fun ctcGreedyDecode(logits: Any?): String {
        // logits shape: [1, T, C] where C = number of characters + 1 (blank)
        val output = when (logits) {
            is Array<*> -> logits
            else        -> return ""
        }

        val batch = output[0] as? Array<*> ?: return ""
        val sb    = StringBuilder()
        var prevChar = -1

        for (t in batch.indices) {
            val scores = when (val step = batch[t]) {
                is FloatArray -> step
                is Array<*>   -> (step as Array<Float>).toFloatArray()
                else          -> continue
            }

            var maxIdx   = 0
            var maxScore = scores[0]
            for (c in scores.indices) {
                if (scores[c] > maxScore) { maxScore = scores[c]; maxIdx = c }
            }

            // CTC blank is typically the last index
            val blankIdx = scores.size - 1
            if (maxIdx != blankIdx && maxIdx != prevChar) {
                val charIdx = maxIdx
                if (charIdx < CHAR_SET.length) {
                    sb.append(CHAR_SET[charIdx])
                }
            }
            prevChar = maxIdx
        }

        return sb.toString().trim()
    }

    // ── Crop a text region from the original bitmap ───────────────────────────

    private fun cropRegion(bitmap: Bitmap, box: TextBox): Bitmap? {
        return try {
            val margin = 4
            val x = (box.x1 - margin).coerceAtLeast(0)
            val y = (box.y1 - margin).coerceAtLeast(0)
            val w = (box.x2 - box.x1 + margin * 2).coerceAtMost(bitmap.width  - x)
            val h = (box.y2 - box.y1 + margin * 2).coerceAtMost(bitmap.height - y)
            if (w <= 0 || h <= 0) null
            else Bitmap.createBitmap(bitmap, x, y, w, h)
        } catch (e: Exception) { null }
    }

    // ── Load asset bytes ──────────────────────────────────────────────────────

    private fun loadAssetBytes(assetPath: String): ByteArray? {
        return try {
            // Strip 'assets/' prefix if present — Android AssetManager uses relative path
            val path = assetPath.removePrefix("assets/")
            context.assets.open(path).use { it.readBytes() }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load asset: $assetPath — ${e.message}")
            null
        }
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    fun close() {
        detSession?.close()
        recSession?.close()
        env?.close()
        detSession  = null
        recSession  = null
        env         = null
        initialized = false
    }
}

// ── Data types ────────────────────────────────────────────────────────────────

data class TextBox(val x1: Int, val y1: Int, val x2: Int, val y2: Int) {
    fun toPolygonList(): List<List<Double>> = listOf(
        listOf(x1.toDouble(), y1.toDouble()),
        listOf(x2.toDouble(), y1.toDouble()),
        listOf(x2.toDouble(), y2.toDouble()),
        listOf(x1.toDouble(), y2.toDouble()),
    )
}

// android/app/src/main/kotlin/com/sightmate/blindassist/MLKitOcrHelper.kt
// MLKit OCR helper — fallback when ONNX models are not bundled

package com.sightmate.blindassist

import android.content.Context
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

object MLKitOcrHelper {

    fun recognizeBytes(context: Context, jpegBytes: ByteArray): String {
        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
            ?: return ""

        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val image      = InputImage.fromBitmap(bitmap, 0)

        // Block on result using CountDownLatch for background thread usage
        var result = ""
        val latch  = java.util.concurrent.CountDownLatch(1)

        recognizer.process(image)
            .addOnSuccessListener { recognized ->
                result = recognized.text.trim()
                latch.countDown()
            }
            .addOnFailureListener {
                latch.countDown()
            }

        latch.await(3, java.util.concurrent.TimeUnit.SECONDS)
        recognizer.close()
        return result
    }
}

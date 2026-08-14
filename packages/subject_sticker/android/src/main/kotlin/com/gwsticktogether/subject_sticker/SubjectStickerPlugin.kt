package com.gwsticktogether.subject_sticker

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * On-device subject cutout via ML Kit Subject Segmentation (Play Services).
 *
 * One method: `cutout {path}` -> transparent PNG bytes of the foreground,
 * or a FlutterError (`decode-failed` / `no-subject` / `segmentation-failed`).
 */
class SubjectStickerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "subject_sticker")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cutout" -> cutout(call.argument<String>("path"), result)
            else -> result.notImplemented()
        }
    }

    private fun cutout(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("bad-args", "missing 'path'", null)
            return
        }
        val image: InputImage
        try {
            // fromFilePath applies EXIF orientation, matching what the user sees.
            image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            result.error("decode-failed", e.message, null)
            return
        }
        // One-shot client per call: matches the previous per-call lifecycle and
        // keeps no native state between edits.
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder().enableForegroundBitmap().build()
        )
        segmenter.process(image)
            .addOnSuccessListener { segmentation ->
                val bitmap: Bitmap? = segmentation.foregroundBitmap
                if (bitmap == null) {
                    result.error("no-subject", "no foreground returned", null)
                } else {
                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    result.success(out.toByteArray())
                }
                segmenter.close()
            }
            .addOnFailureListener { e ->
                result.error("segmentation-failed", e.message, null)
                segmenter.close()
            }
    }
}

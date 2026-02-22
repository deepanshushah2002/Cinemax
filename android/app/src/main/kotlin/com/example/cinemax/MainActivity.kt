package com.example.cinemax

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()


//package com.example.cinemax
//
//import android.content.ContentUris
//import android.database.Cursor
//import android.os.Build
//import android.provider.MediaStore
//import io.flutter.embedding.android.FlutterActivity
//import io.flutter.embedding.engine.FlutterEngine
//import io.flutter.plugin.common.MethodCall
//import io.flutter.plugin.common.MethodChannel
//
//class MainActivity : FlutterActivity() {
//
//    private val channel = "cinemax/mediastore"
//
//    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
//        super.configureFlutterEngine(flutterEngine)
//
//        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
//            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
//                when (call.method) {
//                    "queryVideos" -> result.success(queryVideos())
//                    "getSdkInt"   -> result.success(Build.VERSION.SDK_INT)
//                    else          -> result.notImplemented()
//                }
//            }
//    }
//
//    private fun queryVideos(): List<Map<String, Any>> {
//        val videos = mutableListOf<Map<String, Any>>()
//
//        val collection =
//            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
//                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
//            else
//                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
//
//        val projection = arrayOf(
//            MediaStore.Video.Media._ID,
//            MediaStore.Video.Media.DISPLAY_NAME,
//            MediaStore.Video.Media.DATA,
//            MediaStore.Video.Media.SIZE,
//            MediaStore.Video.Media.DURATION,
//            MediaStore.Video.Media.DATE_MODIFIED
//        )
//
//        val sortOrder = "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
//
//        val cursor: Cursor? = contentResolver.query(
//            collection, projection, null, null, sortOrder
//        )
//
//        cursor?.use { c: Cursor ->
//            val idCol       = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
//            val nameCol     = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
//            val dataCol     = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
//            val sizeCol     = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
//            val durationCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
//
//            while (c.moveToNext()) {
//                val id       = c.getLong(idCol)
//                val name     = c.getString(nameCol) ?: ""
//                val path     = c.getString(dataCol) ?: ""
//                val size     = c.getLong(sizeCol)
//                val duration = c.getLong(durationCol)
//
//                val contentUri = ContentUris.withAppendedId(
//                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id
//                ).toString()
//
//                videos.add(
//                    mapOf(
//                        "uri"      to contentUri,
//                        "path"     to path,
//                        "name"     to name,
//                        "size"     to size,
//                        "duration" to duration
//                    )
//                )
//            }
//        }
//
//        return videos
//    }
//}

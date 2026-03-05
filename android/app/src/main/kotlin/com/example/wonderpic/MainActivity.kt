package com.example.wonderpic

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Force plugin registration to avoid MissingPluginException on some builds/devices.
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }
}

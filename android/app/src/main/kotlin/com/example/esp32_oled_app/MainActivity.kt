package com.example.esp32_oled_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        WifiScanPlugin().registerWith(flutterEngine, applicationContext)
    }
}

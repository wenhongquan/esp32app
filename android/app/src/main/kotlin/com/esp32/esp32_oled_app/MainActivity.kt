package com.esp32.esp32_oled_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.example.esp32_oled_app.WifiScanPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WifiScanPlugin().registerWith(flutterEngine, applicationContext)
    }
}

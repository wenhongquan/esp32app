package com.example.esp32_oled_app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class WifiScanPlugin: MethodCallHandler {
  private var context: Context? = null

  companion object {
    const val CHANNEL = "wifi_scan"
    const val METHOD_SCAN = "scan"
    const val METHOD_GET = "get"
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      METHOD_SCAN -> {
        if (context == null) {
          result.error("NO_CONTEXT", "Context is null", null)
          return
        }
        
        try {
          val wifiManager = context!!.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
          val networks = wifiManager.scanResults
          val wifiList = mutableListOf<String>()
          
          for (network in networks) {
            val ssid = network.SSID
            if (ssid.isNotEmpty() && !wifiList.contains(ssid)) {
              wifiList.add(ssid)
            }
          }
          
          result.success(wifiList)
        } catch (e: Exception) {
          result.error("SCAN_ERROR", e.message, null)
        }
      }
      METHOD_GET -> {
        if (context == null) {
          result.error("NO_CONTEXT", "Context is null", null)
          return
        }
        
        try {
          val wifiManager = context!!.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
          val networks = wifiManager.scanResults
          val wifiList = mutableListOf<String>()
          
          for (network in networks) {
            val ssid = network.SSID
            if (ssid.isNotEmpty() && !wifiList.contains(ssid)) {
              wifiList.add(ssid)
            }
          }
          
          result.success(wifiList)
        } catch (e: Exception) {
          result.error("GET_ERROR", e.message, null)
        }
      }
      else -> result.notImplemented()
    }
  }

  fun registerWith(flutterEngine: FlutterEngine, context: Context) {
    this.context = context
    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    channel.setMethodCallHandler(this)
  }
}

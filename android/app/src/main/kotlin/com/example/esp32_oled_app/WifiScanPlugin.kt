package com.example.esp32_oled_app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.os.Build
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.embedding.FlutterPlugin

class WifiScanPlugin: FlutterPlugin, MethodCallHandler {
  private var context: Context? = null
  private var pendingResult: Result? = null

  companion object {
    const val CHANNEL = "wifi_scan"
    const val METHOD_SCAN = "scan"
    const val METHOD_GET = "get"
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
    channel.setMethodCallHandler(this)
    this.context = binding.applicationContext
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = null
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      METHOD_SCAN -> performWifiScan(result)
      METHOD_GET -> getWifiList(result)
      else -> result.notImplemented()
    }
  }

  private fun performWifiScan(result: Result) {
    if (context == null) {
      result.error("NO_CONTEXT", "Context is null", null)
      return
    }

    val wifiManager = context!!.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    // 检查位置权限 (Android 10+ 需要)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      if (ContextCompat.checkSelfPermission(context!!, Manifest.permission.ACCESS_FINE_LOCATION) 
          != PackageManager.PERMISSION_GRANTED) {
        result.error("PERMISSION_DENIED", "Location permission required for WiFi scan", null)
        return
      }
    }

    val scanReceiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context?, intent: Intent?) {
        context!!.unregisterReceiver(this)
        val success = intent?.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false) ?: false
        
        val wifiList = getWifiListSync(wifiManager)
        if (wifiList.isNotEmpty()) {
          result.success(wifiList)
        } else {
          // 如果scan失败，尝试返回缓存结果
          result.success(getWifiListSync(wifiManager))
        }
      }
    }

    try {
      val intentFilter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
      context!!.registerReceiver(scanReceiver, intentFilter)
      
      val scanStarted = wifiManager.startScan()
      if (!scanStarted) {
        // 如果无法启动扫描（可能是权限或频率限制），返回缓存结果
        context!!.unregisterReceiver(scanReceiver)
        result.success(getWifiListSync(wifiManager))
      }
    } catch (e: Exception) {
      // 出错时返回缓存结果
      try {
        context?.unregisterReceiver(scanReceiver)
      } catch (ignored: Exception) {}
      result.success(getWifiListSync(wifiManager))
    }
  }

  private fun getWifiList(result: Result) {
    if (context == null) {
      result.error("NO_CONTEXT", "Context is null", null)
      return
    }

    try {
      val wifiManager = context!!.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
      val wifiList = getWifiListSync(wifiManager)
      result.success(wifiList)
    } catch (e: Exception) {
      result.error("GET_ERROR", e.message, null)
    }
  }

  private fun getWifiListSync(wifiManager: WifiManager): List<String> {
    val networks = wifiManager.scanResults
    val wifiList = mutableListOf<String>()
    
    for (network in networks) {
      val ssid = network.SSID
      if (ssid.isNotEmpty() && !wifiList.contains(ssid)) {
        wifiList.add(ssid)
      }
    }
    
    return wifiList
  }

  fun registerWith(flutterEngine: FlutterEngine, context: Context) {
    this.context = context
    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    channel.setMethodCallHandler(this)
  }
}

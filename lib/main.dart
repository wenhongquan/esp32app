import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:wifi_scan/wifi_scan.dart';

const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String charSsidUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
const String charPasswordUuid = "beb5483e-36e2-4688-b7f5-ea07361b26a8";
const String charDisplayUuid = "beb5483e-36e3-4688-b7f5-ea07361b26a8";
const String charCommandUuid = "beb5483e-36e4-4688-b7f5-ea07361b26a8";
const String charStatusUuid = "beb5483e-36e5-4688-b7f5-ea07361b26a8";
const String charImageUuid = "beb5483e-36e6-4688-b7f5-ea07361b26a8";
const String charMqttUuid = "beb5483e-36e7-4688-b7f5-ea07361b26a8";

const int cmdConnectWifi = 0x01;
const int cmdClearConfig = 0x02;
const int cmdDisconnectWifi = 0x03;
const int cmdRestart = 0x04;
const int cmdShowText = 0x06;
const int cmdShowImage = 0x07;
const int cmdLedOn = 0x08;
const int cmdLedOff = 0x09;
const int cmdLedBlink = 0x0A;
const int cmdMqttConnect = 0x0B;
const int cmdShowClock = 0x0C; // 显示时钟命令

const int OLED_WIDTH = 72;
const int OLED_HEIGHT = 40;
const int IMAGE_SIZE = OLED_WIDTH * OLED_HEIGHT ~/ 8;

void main() => runApp(const ESP32OLEDApp());

class ESP32OLEDApp extends StatelessWidget {
  const ESP32OLEDApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 OLED',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A90D9)),
        useMaterial3: true,
      ),
      home: const ScanPage(),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  List<ScanResult> results = [];
  bool scanning = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on)
      _scan();
  }

  Future<void> _scan() async {
    if (scanning) return;
    setState(() {
      scanning = true;
      results.clear();
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
    FlutterBluePlus.scanResults.listen((r) {
      for (var e in r) {
        if (e.device.platformName.contains('ESP32') ||
            e.device.platformName.contains('OLED')) {
          if (!results.any((x) => x.device.remoteId == e.device.remoteId))
            setState(() => results.add(e));
        }
      }
    });
    await Future.delayed(const Duration(seconds: 6));
    setState(() => scanning = false);
  }

  void _connect(BluetoothDevice device) async {
    FlutterBluePlus.stopScan();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DevicePage(device: device)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('连接失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 OLED 配网'),
        actions: [
          IconButton(
            icon: Icon(scanning ? Icons.stop : Icons.refresh),
            onPressed: scanning ? null : _scan,
          ),
        ],
      ),
      body: results.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth_searching,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    scanning ? '扫描中...' : '未发现设备',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.devices)),
                title: Text(results[i].device.platformName),
                subtitle: Text(results[i].device.remoteId.str),
                onTap: () => _connect(results[i].device),
              ),
            ),
    );
  }
}

class DevicePage extends StatefulWidget {
  final BluetoothDevice device;
  const DevicePage({super.key, required this.device});
  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  BluetoothCharacteristic? cSSID, cPass, cDisplay, cCmd, cStatus, cImage, cMqtt;
  final ssidC = TextEditingController();
  final passC = TextEditingController();
  final displayC = TextEditingController();
  final mqttServerC = TextEditingController();
  final mqttPortC = TextEditingController(text: '1883');
  final mqttTopicC = TextEditingController(text: 'esp32/oled/control');
  bool loading = true;
  String errMsg = '';
  Map<String, dynamic> status = {};
  StreamSubscription? sub;
  final ImagePicker _picker = ImagePicker();
  Timer? _clockTimer;
  Timer? _wifiScanTimer;
  bool _isClockMode = false;
  List<ScanResult> allResults = [];
  List<String> wifiList = [];
  bool wifiScanning = false;
  void initState() {
    super.initState();
    _init();
    _startWifiAutoScan();
  }

  // 自动扫描 WiFi（每5秒刷新一次）
  void _startWifiAutoScan() {
    _scanWifiNetworks();
    _wifiScanTimer?.cancel();
    _wifiScanTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _scanWifiNetworks();
    });
  }

  String _decode(List<int> d) {
    if (d.isEmpty) return '';
    try {
      return utf8.decode(d);
    } catch (e) {
      var valid = d.where((b) => b >= 32 || b == 10 || b == 13).toList();
      try {
        return utf8.decode(valid);
      } catch (_) {
        return '';
      }
    }
  }

  Future<void> _init() async {
    try {
      var svcs = await widget.device.discoverServices();
      bool found = false;
      for (var s in svcs) {
        if (s.uuid.str128.toUpperCase() == serviceUuid.toUpperCase()) {
          found = true;
          for (var c in s.characteristics) {
            var u = c.uuid.str128.toUpperCase();
            if (u == charSsidUuid.toUpperCase())
              cSSID = c;
            else if (u == charPasswordUuid.toUpperCase())
              cPass = c;
            else if (u == charDisplayUuid.toUpperCase())
              cDisplay = c;
            else if (u == charCommandUuid.toUpperCase())
              cCmd = c;
            else if (u == charStatusUuid.toUpperCase()) {
              cStatus = c;
              if (c.properties.notify) {
                await c.setNotifyValue(true);
                sub = c.lastValueStream.listen((d) => _onStatus(d));
              }
            } else if (u == charImageUuid.toUpperCase())
              cImage = c;
            else if (u == charMqttUuid.toUpperCase())
              cMqtt = c;
          }
        }
      }
      if (!found) throw Exception('未找到目标服务');
      setState(() => loading = false);
    } catch (e) {
      setState(() {
        errMsg = '$e';
        loading = false;
      });
    }
  }

  void _onStatus(List<int> d) {
    if (d.isEmpty) return;
    try {
      var json = _decode(d);
      if (json.isNotEmpty) {
        var s = jsonDecode(json);
        setState(() {
          status = s;
          if (s['ssid'] != null) ssidC.text = s['ssid'];
          if (s['displayText'] != null) displayC.text = s['displayText'];
          // WiFi连接成功后自动校准时间
          if (s['wifiConnected'] == true && !_isClockMode) {
            _startClockMode();
          }
        });
      }
    } catch (e) {}
  }

  // 扫描 WiFi 网络
  Future<void> _scanWifiNetworks() async {
    setState(() => wifiScanning = true);
    try {
      final WiFiScan _wifiScan = WiFiScan.instance;

      // 先尝试获取已有结果
      final canGet = await _wifiScan.canGetScannedResults(askPermissions: true);
      if (canGet == CanGetScannedResults.yes) {
        final results = await _wifiScan.getScannedResults();
        setState(() {
          wifiList = results
              .where((ap) => ap.ssid.isNotEmpty)
              .map((ap) => ap.ssid)
              .toSet()
              .toList();
        });
      } else {
        // 需要开始扫描
        final canStart = await _wifiScan.canStartScan(askPermissions: true);
        if (canStart == CanStartScan.yes) {
          await _wifiScan.startScan();
          final results = await _wifiScan.getScannedResults();
          setState(() {
            wifiList = results
                .where((ap) => ap.ssid.isNotEmpty)
                .map((ap) => ap.ssid)
                .toSet()
                .toList();
          });
        }
      }
    } catch (e) {
      print('WiFi 扫描失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('WiFi 扫描失败: $e')));
      }
    }
    setState(() => wifiScanning = false);
  }

  Future<void> _cmd(int v) async {
    if (cCmd == null) return;
    await cCmd!.write([v]);
  }

  // 切换到时钟模式
  void _toggleClockMode() {
    if (_isClockMode) {
      // 停止时钟
      _clockTimer?.cancel();
      _isClockMode = false;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('时钟模式已关闭')));
    } else {
      // 启动时钟
      _startClockMode();
    }
  }

  // 启动时钟模式
  void _startClockMode() {
    _isClockMode = true;
    setState(() {});

    // 立即显示一次时间
    _updateClockDisplay();

    // 每秒更新一次
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateClockDisplay();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('时钟模式已启动')));
  }

  // 更新时钟显示
  void _updateClockDisplay() {
    if (cDisplay == null || !_isClockMode) return;

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final dateStr = '${now.month}/${now.day}';
    final displayStr = '$timeStr\n$dateStr';

    try {
      cDisplay!.write(utf8.encode(displayStr));
      _cmd(cmdShowText);
    } catch (e) {}
  }

  Uint8List _convertToBitmap(Uint8List imageBytes) {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('无法解码图片');

    double scaleW = OLED_WIDTH / image.width;
    double scaleH = OLED_HEIGHT / image.height;
    double scale = (scaleW < scaleH) ? scaleW : scaleH;

    int newWidth = (image.width * scale).round().clamp(1, OLED_WIDTH);
    int newHeight = (image.height * scale).round().clamp(1, OLED_HEIGHT);

    img.Image resized = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
    );

    Uint8List bitmap = Uint8List(IMAGE_SIZE);
    for (int i = 0; i < IMAGE_SIZE; i++) bitmap[i] = 0x00;

    int offsetX = (OLED_WIDTH - newWidth) ~/ 2;
    int offsetY = (OLED_HEIGHT - newHeight) ~/ 2;

    int bytesPerRow = (OLED_WIDTH + 7) ~/ 8;

    for (int y = 0; y < newHeight; y++) {
      int bmpY = offsetY + y;
      if (bmpY < 0 || bmpY >= OLED_HEIGHT) continue;

      for (int x = 0; x < newWidth; x++) {
        int bmpX = offsetX + x;
        if (bmpX < 0 || bmpX >= OLED_WIDTH) continue;

        var pixel = resized.getPixel(x, y);
        int brightness =
            (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) ~/ 3;
        bool isBlack = brightness < 128;

        int bytePos = bmpY * bytesPerRow + (bmpX ~/ 8);
        int bitIdx = 7 - (bmpX % 8);

        if (bytePos >= 0 && bytePos < IMAGE_SIZE) {
          if (isBlack) {
            bitmap[bytePos] |= (1 << bitIdx);
          } else {
            bitmap[bytePos] &= ~(1 << bitIdx);
          }
        }
      }
    }
    return bitmap;
  }

  Future<void> _pickAndUploadImage() async {
    // 停止时钟模式
    if (_isClockMode) {
      _clockTimer?.cancel();
      _isClockMode = false;
      setState(() {});
    }

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('处理图片中...'),
            ],
          ),
        ),
      );
      var bytes = await image.readAsBytes();
      var bitmap = _convertToBitmap(bytes);
      await _cmd(cmdShowImage);
      const chunkSize = 20;
      int offset = 0;
      while (offset < bitmap.length) {
        int len = (offset + chunkSize > bitmap.length)
            ? (bitmap.length - offset)
            : chunkSize;
        var chunk = bitmap.sublist(offset, offset + len);
        await cImage!.write(chunk);
        offset += len;
        await Future.delayed(const Duration(milliseconds: 10));
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片已发送')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    }
  }

  Future<void> _saveWifi() async {
    if (ssidC.text.isEmpty) return;
    // 清除之前保存的 WiFi 配置
    await _cmd(cmdClearConfig);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await cSSID!.write(utf8.encode(ssidC.text));
      await cPass!.write(utf8.encode(passC.text));
      await _cmd(cmdConnectWifi);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已发送')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    }
  }

  Future<void> _saveDisplay() async {
    // 停止时钟模式
    if (_isClockMode) {
      _clockTimer?.cancel();
      _isClockMode = false;
      setState(() {});
    }

    if (displayC.text.isEmpty) return;
    try {
      await cDisplay!.write(utf8.encode(displayC.text));
      await _cmd(cmdShowText);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已更新')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('失败: $e')));
    }
  }

  Future<void> _saveMqtt() async {
    if (mqttServerC.text.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      String mqttConfig =
          "${mqttServerC.text}:${mqttPortC.text}:${mqttTopicC.text}";
      await cMqtt!.write(utf8.encode(mqttConfig));
      await _cmd(cmdMqttConnect);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('MQTT已配置')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('失败: $e')));
      }
    }
  }

  Future<void> _setLed(bool on) async {
    await _cmd(on ? cmdLedOn : cmdLedOff);
  }

  @override
  void dispose() {
    _wifiScanTimer?.cancel();
    _clockTimer?.cancel();
    sub?.cancel();
    widget.device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.platformName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'disconnect') {
                widget.device.disconnect();
                Navigator.pop(context);
              } else if (v == 'restart')
                await _cmd(cmdRestart);
              else if (v == 'clear')
                await _cmd(cmdClearConfig);
              else if (v == 'wifi_off')
                await _cmd(cmdDisconnectWifi);
              else if (v == 'led_on')
                await _setLed(true);
              else if (v == 'led_off')
                await _setLed(false);
              else if (v == 'led_blink')
                await _cmd(cmdLedBlink);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'led_on', child: Text('蓝灯开')),
              PopupMenuItem(value: 'led_off', child: Text('蓝灯关')),
              PopupMenuItem(value: 'led_blink', child: Text('蓝灯闪烁')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'wifi_off', child: Text('断开WiFi')),
              PopupMenuItem(value: 'clear', child: Text('清除配置')),
              PopupMenuItem(value: 'restart', child: Text('重启设备')),
              PopupMenuItem(value: 'disconnect', child: Text('断开连接')),
            ],
          ),
        ],
      ),
      body: loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    errMsg.isEmpty ? '连接中...' : errMsg,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            status['wifiConnected'] == true
                                ? Icons.wifi
                                : Icons.wifi_off,
                            color: status['wifiConnected'] == true
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status['wifiConnected'] == true
                                      ? 'WiFi已连接'
                                      : 'WiFi未连接',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (status['mqttConnected'] == true)
                                  Text(
                                    'MQTT已连接',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green,
                                    ),
                                  ),
                                if (_isClockMode)
                                  Text(
                                    '时钟模式运行中',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'WiFi配置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          wifiScanning ? Icons.hourglass_empty : Icons.refresh,
                        ),
                        onPressed: wifiScanning ? null : _scanWifiNetworks,
                        tooltip: '扫描WiFi',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // WiFi 下拉选择
                  DropdownButtonFormField<String>(
                    value: ssidC.text.isEmpty ? null : ssidC.text,
                    decoration: const InputDecoration(
                      labelText: 'WiFi名称',
                      border: OutlineInputBorder(),
                    ),
                    items: wifiList
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ssidC.text = value;
                        passC.text = '';
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passC,
                    decoration: const InputDecoration(
                      labelText: 'WiFi密码',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveWifi,
                      child: const Text('保存并连接'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'OLED显示',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: displayC,
                    decoration: const InputDecoration(
                      labelText: '显示文字',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveDisplay,
                      child: const Text('更新文字'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 时钟切换按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _toggleClockMode,
                      icon: Icon(
                        _isClockMode ? Icons.timer_off : Icons.access_time,
                      ),
                      label: Text(_isClockMode ? '关闭时钟' : '显示时钟'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isClockMode
                            ? Colors.orange
                            : Colors.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickAndUploadImage,
                      icon: const Icon(Icons.image),
                      label: const Text('上传图片显示（居中）'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'MQTT配置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mqttServerC,
                    decoration: const InputDecoration(
                      labelText: 'MQTT服务器',
                      border: OutlineInputBorder(),
                      hintText: 'broker.example.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mqttPortC,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: mqttTopicC,
                    decoration: const InputDecoration(
                      labelText: '控制主题',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveMqtt,
                      child: const Text('保存MQTT配置'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    '蓝灯控制',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _setLed(true),
                          child: const Text('开'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _setLed(false),
                          child: const Text('关'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _cmd(cmdLedBlink),
                          child: const Text('闪烁'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

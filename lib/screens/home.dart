import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../src/device/device_manager.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _scanTimer;
  static const String _autoScanKey = 'auto_scan';

  @override
  void initState() {
    super.initState();
    // 初始化时扫描设备
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final deviceManager = context.read<DeviceManager>();
      _loadAutoScanSetting(deviceManager);
      deviceManager.searchDevices();
    });
  }

  Future<void> _loadAutoScanSetting(DeviceManager deviceManager) async {
    final prefs = await SharedPreferences.getInstance();
    final autoScan = prefs.getBool(_autoScanKey) ?? false;
    deviceManager.setAutoScan(autoScan);
    if (autoScan) {
      _startAutoScan();
    }
  }

  Future<void> _saveAutoScanSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoScanKey, value);
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  void _startAutoScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final deviceManager = context.read<DeviceManager>();
      if (!deviceManager.isScanning) {
        deviceManager.searchDevices();
      }
    });
  }

  void _stopAutoScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('我的设备'),
        commandBar: Consumer<DeviceManager>(
          builder: (context, deviceManager, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (deviceManager.isScanning)
                  const ProgressRing(
                    strokeWidth: 2.0,
                  ),
                const SizedBox(width: 8),
                ToggleSwitch(
                  checked: deviceManager.autoScan,
                  onChanged: (value) async {
                    deviceManager.setAutoScan(value);
                    await _saveAutoScanSetting(value);
                    if (value) {
                      _startAutoScan();
                    } else {
                      _stopAutoScan();
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  deviceManager.autoScan ? '自动扫描中' : '手动扫描',
                  style: TextStyle(
                    color: FluentTheme.of(context).inactiveBackgroundColor,
                  ),
                ),
                if (!deviceManager.autoScan) ...[
                  const SizedBox(width: 8),
                  Button(
                    child: const Text('扫描设备'),
                    onPressed: deviceManager.isScanning
                        ? null
                        : () => deviceManager.manualScan(),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Consumer<DeviceManager>(
            builder: (context, deviceManager, child) {
              final devices = deviceManager.availableDevices;

              if (devices.isEmpty) {
                return const Center(
                  child: Text('未发现设备'),
                );
              }

              return SingleChildScrollView(
                child: Center(
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: devices.map((device) {
                      return SizedBox(
                        width: 360,
                        height: 400,
                        child: Card(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    device.displayName,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _buildInfoRow(
                                      context, '设备序列号', device.sn, true),
                                  _buildDoubleInfoRow(
                                    context,
                                    '设备型号',
                                    device.model ?? '未知',
                                    '软件版本',
                                    device.swVer ?? '未知',
                                  ),
                                  _buildDoubleInfoRow(
                                    context,
                                    '硬件版本',
                                    device.hwVer ?? '未知',
                                    '引导版本',
                                    device.blVer ?? '未知',
                                  ),
                                  const SizedBox(height: 20),
                                  Image.asset('assets/images/hslink.png',
                                      width: 120),
                                  const SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      FilledButton(
                                        child: Text(
                                          device.connected ? '断开' : '连接',
                                        ),
                                        onPressed: () {
                                          if (device.connected) {
                                            deviceManager.disconnectDevice();
                                          } else {
                                            deviceManager
                                                .connectDevice(device.sn);
                                          }
                                        },
                                      ),
                                      if (device.connected) ...[
                                        const SizedBox(width: 8),
                                        Button(
                                          child: const Text('设置'),
                                          onPressed: () {
                                            context.go(
                                                '/device_settings?sn=${device.sn}');
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      BuildContext context, String label, String value1, bool ellipsis) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label),
          ),
          SizedBox(
            width: 200,
            child: Text(
              value1,
              style: TextStyle(color: FluentTheme.of(context).accentColor),
              overflow: ellipsis ? TextOverflow.ellipsis : TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoubleInfoRow(BuildContext context, String label1, String value1,
      String label2, String value2) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(label1),
          ),
          SizedBox(
            width: 80,
            child: Text(
              value1,
              style: TextStyle(color: FluentTheme.of(context).accentColor),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 65,
            child: Text(label2),
          ),
          SizedBox(
            width: 70,
            child: Text(
              value2,
              style: TextStyle(color: FluentTheme.of(context).accentColor),
            ),
          ),
        ],
      ),
    );
  }
}

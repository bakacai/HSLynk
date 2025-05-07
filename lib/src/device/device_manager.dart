import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hslynk/src/rust/api/hslink_backend.dart';

class Device {
  final String sn;
  bool connected;
  bool infoLoaded;
  String? nickname;
  String? model;
  String? hwVer;
  String? swVer;
  String? blVer;

  Device({
    required this.sn,
    this.connected = false,
    this.infoLoaded = false,
    this.nickname,
    this.model,
    this.hwVer,
    this.swVer,
    this.blVer,
  });

  // 获取显示名称
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) {
      return nickname!;
    }
    // 如果序列号长度小于6，则返回完整序列号
    return sn.length <= 6 ? sn : sn.substring(0, 6);
  }
}

class DeviceManager extends ChangeNotifier {
  final List<Device> _availableDevices = [];
  String? _connectedDeviceSn;
  bool _isScanning = false;
  bool _autoScan = true;
  static const String _autoScanKey = 'auto_scan_enabled';

  List<Device> get availableDevices => _availableDevices;
  String? get connectedDeviceSn => _connectedDeviceSn;
  bool get isScanning => _isScanning;
  bool get autoScan => _autoScan;

  DeviceManager() {
    // 从本地存储加载自动扫描设置
    _loadAutoScanSetting();
  }

  // 加载自动扫描设置
  Future<void> _loadAutoScanSetting() async {
    final prefs = await SharedPreferences.getInstance();
    _autoScan = prefs.getBool(_autoScanKey) ?? true;
    notifyListeners();
  }

  // 保存自动扫描设置
  Future<void> _saveAutoScanSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoScanKey, value);
  }

  // 设置自动扫描
  Future<void> setAutoScan(bool value) async {
    if (_autoScan == value) return;
    _autoScan = value;
    await _saveAutoScanSetting(value);
    notifyListeners();
  }

  // 手动扫描设备
  Future<void> manualScan() async {
    if (_isScanning) return;
    await searchDevices();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 扫描设备
  Future<void> searchDevices() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      debugPrint("正在搜索设备...");
      final newDeviceList = await hslinkListDevice();
      debugPrint("设备列表: $newDeviceList");

      // 检查设备是否有变化
      final oldDeviceSns =
          _availableDevices.map((device) => device.sn).toList();
      final newDeviceSns = newDeviceList;

      // 检查设备是否已移除
      final removedDevices =
          oldDeviceSns.where((sn) => !newDeviceSns.contains(sn)).toList();
      if (removedDevices.isNotEmpty) {
        debugPrint("设备已移除: ${removedDevices.join(', ')}");

        // 移除已拔出的设备
        _availableDevices
            .removeWhere((device) => removedDevices.contains(device.sn));

        // 如果当前连接的设备被移除，断开连接
        if (_connectedDeviceSn != null &&
            removedDevices.contains(_connectedDeviceSn)) {
          debugPrint("已连接的设备 $_connectedDeviceSn 已被移除");
          await disconnectDevice();
        }
      }

      // 检查是否有新设备
      final newDevices =
          newDeviceSns.where((sn) => !oldDeviceSns.contains(sn)).toList();
      for (final newDeviceSn in newDevices) {
        debugPrint("发现新设备: $newDeviceSn");

        // 将新设备添加到列表中
        _availableDevices.add(Device(
          sn: newDeviceSn,
          connected: false,
          infoLoaded: false,
        ));

        // 获取新设备的基本信息
        await getDeviceBasicInfo(newDeviceSn);
      }

      notifyListeners();
    } catch (e) {
      debugPrint("扫描设备失败: $e");
    } finally {
      _isScanning = false;
    }
  }

  // 获取设备基本信息但不连接
  Future<void> getDeviceBasicInfo(String deviceSn) async {
    try {
      // 临时连接设备获取信息
      debugPrint("正在获取设备信息: $deviceSn");
      final ret = await hslinkOpenDevice(serialNumber: deviceSn);
      if (ret != deviceSn) {
        debugPrint("无法打开设备 $deviceSn 获取信息: $ret");
        return;
      }

      // 设备已连接，获取基本信息
      final rsp = await hslinkWriteWaitRsp(
        data: utf8.encode(JsonEncoder().convert({"name": "Hello"})),
        timeout: 1000,
      );

      // 解析设备信息
      final rspJson = jsonDecode(rsp);
      final serial = rspJson["serial"];
      final model = rspJson["model"];
      final version = rspJson["version"];
      final hardware = rspJson["hardware"];
      final bootloader = rspJson["bootloader"];
      final nickname = rspJson["nickname"] ?? "";

      debugPrint("获取到设备 $deviceSn 的信息: model=$model, nickname='$nickname'");
      debugPrint("设备信息原始响应: ${JsonEncoder().convert(rspJson)}");

      // 确保昵称不是undefined或null
      final safeNickname = (nickname == null) ? "" : nickname;

      // 更新设备信息
      final deviceIndex = _availableDevices.indexWhere((d) => d.sn == deviceSn);
      if (deviceIndex >= 0) {
        _availableDevices[deviceIndex] = Device(
          sn: deviceSn,
          nickname: safeNickname.isEmpty ? null : safeNickname,
          model: model,
          hwVer: hardware,
          swVer: version,
          blVer: bootloader,
          infoLoaded: true,
        );

        debugPrint(
            "更新设备信息: sn=${_availableDevices[deviceIndex].sn}, model=${_availableDevices[deviceIndex].model}, nickname=${_availableDevices[deviceIndex].nickname}");
      }

      // 如果这不是当前连接的设备，断开临时连接
      if (deviceSn != _connectedDeviceSn) {
        // 显式断开临时连接
        debugPrint("显式关闭与 $deviceSn 的临时连接");

        // 发送关闭命令
        try {
          await hslinkWriteWaitRsp(
            data: utf8.encode(JsonEncoder().convert({"name": "Close"})),
            timeout: 500,
          );
        } catch (e) {
          debugPrint("发送关闭命令时出错: $e");
        }
      } else {
        debugPrint("设备 $deviceSn 已连接，保持连接");
      }
    } catch (e) {
      debugPrint("获取设备 $deviceSn 信息时出错: $e");
    }
  }

  // 连接设备
  Future<void> connectDevice(String deviceSn) async {
    try {
      // 如果已经连接了其他设备，先断开连接
      if (_connectedDeviceSn != null && _connectedDeviceSn != deviceSn) {
        debugPrint("已连接其他设备 $_connectedDeviceSn，先断开连接");
        await disconnectDevice();
      }

      final ret = await hslinkOpenDevice(serialNumber: deviceSn);
      if (ret == deviceSn) {
        _connectedDeviceSn = deviceSn;
        final deviceIndex =
            _availableDevices.indexWhere((d) => d.sn == deviceSn);
        if (deviceIndex >= 0) {
          _availableDevices[deviceIndex].connected = true;
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint("连接设备 $deviceSn 失败: $e");
    }
  }

  // 断开设备连接
  Future<void> disconnectDevice() async {
    if (_connectedDeviceSn != null) {
      try {
        await hslinkCloseDevice();
        final deviceIndex =
            _availableDevices.indexWhere((d) => d.sn == _connectedDeviceSn);
        if (deviceIndex >= 0) {
          _availableDevices[deviceIndex].connected = false;
        }
        _connectedDeviceSn = null;
        notifyListeners();
      } catch (e) {
        debugPrint("断开设备连接失败: $e");
      }
    }
  }
}

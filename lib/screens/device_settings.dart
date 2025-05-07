import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart' show Material;
import '../src/device/device_manager.dart';
import 'dart:convert';
import '../src/rust/api/hslink_backend.dart';

class DeviceSettings extends StatefulWidget {
  final String deviceSn;

  const DeviceSettings({
    super.key,
    required this.deviceSn,
  });

  @override
  State<DeviceSettings> createState() => _DeviceSettingsState();
}

class _DeviceSettingsState extends State<DeviceSettings> {
  final TextEditingController _nicknameController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;
  String? _successMessage;
  OverlayEntry? _overlayEntry;

  // 性能设置
  bool _speedBoostEnable = false;
  String _swdSimulateMode = 'spi';
  String _jtagSimulateMode = 'spi';
  bool _jtagSingleBitMode = true;
  bool _jtag20pinCompatible = false;

  // 电源设置
  bool _powerPowerOn = false;
  bool _powerPortOn = false;
  double _powerVrefVoltage = 3.3;
  bool _isExternalVref = false;
  String _voltageMode = 'preset';
  final TextEditingController _customVoltageController =
      TextEditingController();
  String? _voltageErrorMsg;
  final List<double> _presetVoltages = [1.8, 3.3, 3.6, 5.0];

  // 复位设置
  final List<String> _resetMode = [];

  // LED设置
  bool _ledEnable = false;
  int _ledBrightness = 50;

  void _showMessage(String message, {bool isError = true}) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(isError ? '错误' : '成功'),
        content: Text(message),
        actions: [
          FilledButton(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // 获取当前设备的设置
    final deviceManager = context.read<DeviceManager>();
    final device = deviceManager.availableDevices.firstWhere(
      (d) => d.sn == widget.deviceSn,
      orElse: () => Device(sn: widget.deviceSn),
    );
    _nicknameController.text = device.nickname ?? '';
    _loadDeviceSettings();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _customVoltageController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceSettings() async {
    try {
      final rsp = await hslinkWriteWaitRsp(
        data: utf8.encode(jsonEncode({"name": "get_setting"})),
        timeout: 1000,
      );

      final rspJson = jsonDecode(rsp);
      debugPrint("加载设备设置: $rspJson");

      if (mounted) {
        setState(() {
          _speedBoostEnable = rspJson["boost"] ?? false;
          _swdSimulateMode = rspJson["swd_port_mode"] ?? 'spi';
          _jtagSimulateMode = rspJson["jtag_port_mode"] ?? 'spi';
          _jtagSingleBitMode = rspJson["jtag_single_bit_mode"] ?? true;
          _jtag20pinCompatible = rspJson["jtag_20pin_compatible"] ?? false;

          final power = rspJson["power"] ?? {};
          _powerPowerOn = power["power_on"] ?? false;
          _powerPortOn = power["port_on"] ?? false;
          _powerVrefVoltage = (power["vref"] ?? 3.3).toDouble();
          _isExternalVref = _powerVrefVoltage == 0;

          _resetMode.clear();
          _resetMode.addAll(List<String>.from(rspJson["reset"] ?? []));

          _ledEnable = rspJson["led"] ?? false;
          _ledBrightness = (rspJson["led_brightness"] ?? 50).toInt();
        });
      }
    } catch (e) {
      debugPrint("加载设备设置失败: $e");
      if (mounted) {
        _showMessage("加载设备设置失败: $e");
      }
    }
  }

  void _toggleResetMode(String mode, bool checked) {
    setState(() {
      if (checked && !_resetMode.contains(mode)) {
        _resetMode.add(mode);
      } else if (!checked && _resetMode.contains(mode)) {
        _resetMode.remove(mode);
      }
    });
  }

  void _selectPresetVoltage(double voltage) {
    setState(() {
      _powerVrefVoltage = voltage;
      _voltageMode = 'preset';
      _customVoltageController.text = voltage.toString();
      _voltageErrorMsg = null;
    });
  }

  void _updateCustomVoltage(String value) {
    setState(() {
      if (value.isEmpty) {
        _voltageErrorMsg = '请输入电压值';
        return;
      }

      final voltage = double.tryParse(value);
      if (voltage == null) {
        _voltageErrorMsg = '请输入有效的数字';
      } else if (voltage < 1.8) {
        _voltageErrorMsg = '电压值不能低于1.8V';
      } else if (voltage > 5.0) {
        _voltageErrorMsg = '电压值不能超过5.0V';
      } else {
        _voltageErrorMsg = null;
        _powerVrefVoltage = double.parse(voltage.toStringAsFixed(1));
        _voltageMode = 'custom';
      }
    });
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // 保存昵称
      final nicknameStr = jsonEncode({
        "name": "set_nickname",
        "nickname": _nicknameController.text,
      });

      var rsp = await hslinkWriteWaitRsp(
        data: utf8.encode(nicknameStr),
        timeout: 1000,
      );

      debugPrint("保存昵称: $rsp");

      var rspJson = jsonDecode(rsp);
      debugPrint("保存昵称: $rspJson");
      if (rspJson["status"] != "success") {
        _showMessage("保存失败：${rspJson["message"] ?? "未知错误"}");
        return;
      }

      // 保存其他设置
      final settingsStr = jsonEncode({
        "name": "settings",
        "data": {
          "boost": _speedBoostEnable,
          "swd_port_mode": _swdSimulateMode,
          "jtag_port_mode": _jtagSimulateMode,
          "jtag_single_bit_mode": _jtagSingleBitMode,
          "jtag_20pin_compatible": _jtag20pinCompatible,
          "power": {
            "power_on": _powerPowerOn,
            "port_on": _powerPortOn,
            "vref": _isExternalVref ? 0 : _powerVrefVoltage
          },
          "reset": _resetMode,
          "led": _ledEnable,
          "led_brightness": _ledBrightness.toInt()
        }
      });

      debugPrint("保存其他设置: $settingsStr");

      rsp = await hslinkWriteWaitRsp(
        data: utf8.encode(settingsStr),
        timeout: 1000,
      );

      debugPrint("保存设备设置: $rsp");

      rspJson = jsonDecode(rsp);
      if (rspJson["status"] == "success") {
        _showMessage("设置已保存", isError: false);
      } else {
        _showMessage("保存失败：${rspJson["message"] ?? "未知错误"}");
      }
    } catch (e) {
      _showMessage("保存失败：$e");
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceManager = context.watch<DeviceManager>();
    final device = deviceManager.availableDevices.firstWhere(
      (d) => d.sn == widget.deviceSn,
      orElse: () => Device(sn: widget.deviceSn),
    );

    if (!device.connected) {
      return ScaffoldPage(
        header: const PageHeader(title: Text('设备设置')),
        content: const Center(
          child: Text('请先连接设备'),
        ),
      );
    }

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('设备设置'),
        commandBar: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isSaving)
              const ProgressRing(
                strokeWidth: 2.0,
              ),
            const SizedBox(width: 8),
            FilledButton(
              child: const Text('保存设置'),
              onPressed: _isSaving ? null : _saveSettings,
            ),
          ],
        ),
      ),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 设备信息
              _buildSection(
                title: '基本设置',
                icon: FluentIcons.device_run,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '设备昵称',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextBox(
                      controller: _nicknameController,
                      placeholder: '请输入设备昵称',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '设置一个易于识别的设备名称',
                      style: TextStyle(
                        fontSize: 12,
                        color: FluentTheme.of(context).inactiveBackgroundColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 下载设置
              _buildSection(
                title: '下载设置',
                icon: FluentIcons.download,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      title: '速度提升',
                      value: _speedBoostEnable,
                      onChanged: (value) =>
                          setState(() => _speedBoostEnable = value),
                      description: '启用速度提升功能可以提高设备性能',
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '接口设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPortModeSelector(
                            title: 'SWD输出方式',
                            value: _swdSimulateMode,
                            onChanged: (value) =>
                                setState(() => _swdSimulateMode = value),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildPortModeSelector(
                            title: 'JTAG输出方式',
                            value: _jtagSimulateMode,
                            onChanged: (value) =>
                                setState(() => _jtagSimulateMode = value),
                          ),
                        ),
                      ],
                    ),
                    if (_jtagSimulateMode == 'spi') ...[
                      const SizedBox(height: 16),
                      _buildToggle(
                        title: 'JTAG_SHIFT加速',
                        value: _jtagSingleBitMode,
                        onChanged: (value) =>
                            setState(() => _jtagSingleBitMode = value),
                        description: '启用JTAG_SHIFT加速功能可以提高JTAG传输速度',
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 兼容性设置
              _buildSection(
                title: '兼容性设置',
                icon: FluentIcons.device_run,
                child: _buildToggle(
                  title: 'JTAG 20针兼容模式',
                  value: _jtag20pinCompatible,
                  onChanged: (value) =>
                      setState(() => _jtag20pinCompatible = value),
                  description: '启用JTAG 20针兼容模式可以支持更多设备',
                ),
              ),

              const SizedBox(height: 20),

              // 电源设置
              _buildSection(
                title: '电源设置',
                icon: FluentIcons.power_button,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildToggle(
                            title: '上电开启电源输出',
                            value: _powerPowerOn,
                            onChanged: (value) =>
                                setState(() => _powerPowerOn = value),
                            description: '设备上电时自动开启电源输出',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildToggle(
                            title: '上电开启IO输出',
                            value: _powerPortOn,
                            onChanged: (value) =>
                                setState(() => _powerPortOn = value),
                            description: '设备上电时自动开启IO输出',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildVoltageSettings(),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 复位设置
              _buildSection(
                title: '复位设置',
                icon: FluentIcons.refresh,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '复位模式',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildResetModeCheckbox(
                          title: 'NRST',
                          description: '使用NRST引脚进行复位',
                          mode: 'nrst',
                        ),
                        _buildResetModeCheckbox(
                          title: 'POR',
                          description: '使用上电复位',
                          mode: 'por',
                        ),
                        _buildResetModeCheckbox(
                          title: 'ARM SWD软复位',
                          description: '使用ARM SWD软复位',
                          mode: 'arm_swd_soft',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // LED设置
              _buildSection(
                title: 'LED设置',
                icon: FluentIcons.light,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggle(
                      title: '启用LED',
                      value: _ledEnable,
                      onChanged: (value) => setState(() => _ledEnable = value),
                      description: '启用设备LED指示灯',
                    ),
                    if (_ledEnable) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'LED亮度',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: _ledBrightness.toDouble(),
                        onChanged: (value) =>
                            setState(() => _ledBrightness = value.toInt()),
                        min: 1,
                        max: 100,
                        divisions: 99,
                        label: '${_ledBrightness}%',
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('1%'),
                          Text('25%'),
                          Text('50%'),
                          Text('75%'),
                          Text('100%'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: FluentTheme.of(context).accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).inactiveBackgroundColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: FluentTheme.of(context).inactiveBackgroundColor,
                  ),
                ),
              ],
            ),
          ),
          ToggleSwitch(
            checked: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildPortModeSelector({
    required String title,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).inactiveBackgroundColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Button(
                  child: const Text('SPI'),
                  onPressed: () => onChanged('spi'),
                  style: ButtonStyle(
                    backgroundColor: ButtonState.all(
                      value == 'spi'
                          ? FluentTheme.of(context).accentColor
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Button(
                  child: const Text('GPIO'),
                  onPressed: () => onChanged('gpio'),
                  style: ButtonStyle(
                    backgroundColor: ButtonState.all(
                      value == 'gpio'
                          ? FluentTheme.of(context).accentColor
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoltageSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).inactiveBackgroundColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '参考电压',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  const Text('外部输入'),
                  const SizedBox(width: 8),
                  ToggleSwitch(
                    checked: _isExternalVref,
                    onChanged: (value) {
                      setState(() {
                        _isExternalVref = value;
                        if (value) {
                          _powerVrefVoltage = 0;
                        } else {
                          _powerVrefVoltage = 3.3;
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          if (!_isExternalVref) ...[
            const SizedBox(height: 16),
            ToggleButton(
              checked: _voltageMode == 'preset',
              onChanged: (value) {
                setState(() {
                  _voltageMode = value ? 'preset' : 'custom';
                  if (!value) {
                    _customVoltageController.text =
                        _powerVrefVoltage.toString();
                  }
                });
              },
              child: Text(_voltageMode == 'preset' ? '预设值' : '自定义'),
            ),
            const SizedBox(height: 16),
            if (_voltageMode == 'preset')
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetVoltages.map((voltage) {
                  return Button(
                    child: Text('${voltage}V'),
                    onPressed: () => _selectPresetVoltage(voltage),
                    style: ButtonStyle(
                      backgroundColor: ButtonState.all(
                        _powerVrefVoltage == voltage
                            ? FluentTheme.of(context).accentColor
                            : Colors.transparent,
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextBox(
                    controller: _customVoltageController,
                    placeholder: '请输入电压值',
                    onChanged: _updateCustomVoltage,
                    suffix: const Text('V'),
                  ),
                  if (_voltageErrorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _voltageErrorMsg!,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildResetModeCheckbox({
    required String title,
    required String description,
    required String mode,
  }) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluentTheme.of(context).inactiveBackgroundColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: _resetMode.contains(mode)
              ? FluentTheme.of(context).accentColor
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            checked: _resetMode.contains(mode),
            onChanged: (value) => _toggleResetMode(mode, value ?? false),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: FluentTheme.of(context).inactiveBackgroundColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

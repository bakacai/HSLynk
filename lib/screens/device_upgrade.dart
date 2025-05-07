import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../src/device/device_manager.dart';
import '../src/rust/api/hslink_backend.dart';
import '../src/utils/crc32.dart';

class DeviceUpgrade extends StatefulWidget {
  final String deviceSn;

  const DeviceUpgrade({
    super.key,
    required this.deviceSn,
  });

  @override
  State<DeviceUpgrade> createState() => _DeviceUpgradeState();
}

class _DeviceUpgradeState extends State<DeviceUpgrade> {
  String? _appFwPath;
  String? _bootloaderFwPath;
  String? _bootloaderPath;
  bool _inBootloader = false;
  Timer? _probeTimer;
  bool _isUpgrading = false;
  double _upgradeProgress = 0.0;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _startProbing();
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    super.dispose();
  }

  void _startProbing() {
    _probeBootloader();
    _probeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _probeBootloader();
    });
  }

  Future<String?> _findBootloaderPath() async {
    try {
      if (Platform.isLinux) {
        // 在 Linux 上先检查 /media 目录
        final mediaDir = Directory('/media');
        if (await mediaDir.exists()) {
          final entities = await mediaDir.list().toList();
          for (final entity in entities) {
            if (entity is Directory) {
              final userDir = Directory('${entity.path}/CHERRYUF2');
              if (await userDir.exists()) {
                debugPrint('在 /media 目录下找到 CHERRYUF2: ${userDir.path}');
                return '${userDir.path}/';
              }
            }
          }
        }

        // 如果 /media 目录下没找到，尝试使用 lsblk 命令
        final result =
            await Process.run('lsblk', ['-f', '-o', 'MOUNTPOINT,LABEL']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('CHERRYUF2')) {
              final parts = line.split(' ').where((s) => s.isNotEmpty).toList();
              if (parts.length >= 2) {
                debugPrint('使用 lsblk 找到 CHERRYUF2: ${parts[0]}');
                return '${parts[0]}/';
              }
            }
          }
        }
      } else if (Platform.isMacOS) {
        // 在 macOS 上使用 diskutil 命令查找 CHERRYUF2 设备
        final result = await Process.run('diskutil', ['list']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('CHERRYUF2')) {
              return '/Volumes/CHERRYUF2/';
            }
          }
        }
      } else if (Platform.isWindows) {
        // 在 Windows 上使用 wmic 命令查找 CHERRYUF2 设备
        final result = await Process.run(
            'wmic', ['logicaldisk', 'get', 'deviceid,volumename']);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final lines = output.split('\n');
          for (final line in lines) {
            if (line.contains('CHERRYUF2')) {
              final parts = line.split(' ').where((s) => s.isNotEmpty).toList();
              if (parts.length >= 2) {
                return '${parts[0]}\\';
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('查找引导加载程序路径失败: $e');
    }
    return null;
  }

  Future<void> _probeBootloader() async {
    try {
      debugPrint('探测引导加载程序');
      final bootloaderPath = await _findBootloaderPath();
      if (!mounted) return;
      setState(() {
        _inBootloader = true;
        _bootloaderPath = bootloaderPath;
      });
    } catch (e) {
      debugPrint("探测引导加载程序失败: $e");
      if (!mounted) return;
      setState(() {
        _inBootloader = false;
        _bootloaderPath = null;
      });
    }
  }

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

  Future<void> _selectAppFirmware() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['uf2'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _appFwPath = result.files.first.path;
        });
      }
    } catch (e) {
      debugPrint("选择应用固件失败: $e");
      if (!mounted) return;
      _showMessage("选择应用固件失败: $e");
    }
  }

  Future<void> _selectBootloaderFirmware() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );

      if (result != null) {
        setState(() {
          _bootloaderFwPath = result.files.single.path;
        });
      }
    } catch (e) {
      debugPrint("选择引导加载程序固件失败: $e");
    }
  }

  Future<void> _enterBootloader() async {
    try {
      await hslinkWrite(
        data: utf8.encode(jsonEncode({"name": "entry_hslink_bl"})),
      );
    } catch (e) {
      debugPrint("进入引导加载程序失败: $e");
    }
  }

  Future<void> _upgradeApp() async {
    if (_appFwPath == null || !_appFwPath!.endsWith('.uf2')) {
      if (!mounted) return;
      _showMessage("请选择有效的 UF2 文件");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isUpgrading = true;
    });

    try {
      // 进入引导加载程序
      await _enterBootloader();
      debugPrint("已发送进入引导加载程序命令");

      // 等待设备进入引导加载程序模式
      await Future.delayed(const Duration(seconds: 4));
      debugPrint("等待设备进入引导加载程序模式");

      // 查找引导加载程序路径
      final bootloaderPath = await _findBootloaderPath();
      if (bootloaderPath == null) {
        throw Exception('未找到引导加载程序盘符');
      }
      debugPrint("找到引导加载程序路径: $bootloaderPath");

      // 复制 UF2 文件到目标盘符
      final file = await File(_appFwPath!).readAsBytes();
      await File('$bootloaderPath/HSLink-Pro.uf2').writeAsBytes(file);
      debugPrint("已复制固件文件到引导加载程序");

      if (!mounted) return;
      _showMessage("应用固件升级成功，设备将自动重启", isError: false);
    } catch (e) {
      debugPrint("应用固件升级失败: $e");
      if (!mounted) return;
      _showMessage("应用固件升级失败: $e");
    } finally {
      if (!mounted) return;
      setState(() {
        _isUpgrading = false;
      });
      // 断开设备连接
      context.read<DeviceManager>().disconnectDevice();
    }
  }

  Future<void> _upgradeBootloader() async {
    if (_bootloaderFwPath == null || !_bootloaderFwPath!.endsWith('.bin')) {
      _showMessage("请选择有效的 BIN 文件");
      return;
    }

    setState(() {
      _isUpgrading = true;
      _upgradeProgress = 0.0;
    });

    try {
      // 擦除引导加载程序
      await hslinkWriteWaitRsp(
        data: utf8.encode(jsonEncode({"name": "erase_bl_b"})),
        timeout: 1000,
      );

      // 读取文件
      final file = await File(_bootloaderFwPath!).readAsBytes();

      // 四字节对齐
      Uint8List alignedFile;
      if (file.length % 4 != 0) {
        alignedFile = Uint8List(file.length + (4 - file.length % 4));
        alignedFile.setAll(0, file);
      } else {
        alignedFile = file;
      }

      // 计算 CRC32
      final crc32Value = Crc32.compute(alignedFile);

      // 分块写入固件
      const blockSize = 512;
      final totalBlocks = (alignedFile.length / blockSize).ceil();
      var currentBlock = 0;

      for (var i = 0; i < alignedFile.length; i += blockSize) {
        final end = (i + blockSize < alignedFile.length)
            ? i + blockSize
            : alignedFile.length;
        final block = alignedFile.sublist(i, end);

        final rsp = await hslinkWriteWaitRsp(
          data: utf8.encode(jsonEncode({
            "name": "write_bl_b",
            "addr": i,
            "len": block.length,
            "data": base64Encode(block),
          })),
          timeout: 1000,
        );

        debugPrint("写入块 $i-$end 响应: $rsp");

        currentBlock++;
        if (mounted) {
          setState(() {
            // 计算写入进度，预留10%给最后的升级命令
            _upgradeProgress = (currentBlock / totalBlocks) * 90;
          });
        }
      }

      debugPrint("crc32Value: ${crc32Value.toRadixString(16).toUpperCase()}");

      // 发送升级命令
      final upgradeCmd = {
        "name": "upgrade_bl",
        "len": alignedFile.length,
        "crc": "0x${crc32Value.toRadixString(16).toUpperCase()}",
      };
      debugPrint("发送升级命令: $upgradeCmd");

      if (mounted) {
        setState(() {
          // 设置进度为90%，表示正在发送升级命令
          _upgradeProgress = 0.9;
        });
      }
      try {
        final rsp = await hslinkWriteWaitRsp(
          data: utf8.encode(jsonEncode(upgradeCmd)),
          timeout: 1000,
        );

        debugPrint("引导加载程序升级响应: $rsp");

        if (mounted) {
          setState(() {
            // 设置进度为100%，表示升级完成
            _upgradeProgress = 1.0;
          });
        }

        var rspJson = jsonDecode(rsp);
        if (rspJson["status"] == "failed") {
          _showMessage("引导加载程序升级失败: ${rspJson["message"]}");
        } else {
          _showMessage("引导加载程序升级成功", isError: false);
        }
      } catch (e) {
        _showMessage("引导加载程序升级成功", isError: false);
      }
    } catch (e) {
      _showMessage("引导加载程序升级失败: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isUpgrading = false;
          _upgradeProgress = 0.0;
        });
        // 断开设备连接
        context.read<DeviceManager>().disconnectDevice();
      }
    }
  }

  Future<void> _downloadFirmware() async {
    const url = 'https://github.com/cherry-embedded/CherryDAP/releases';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  bool _isAppVersionSupported(String? version) {
    if (version == null) return false;

    final parts = version.split('.').map(int.parse).toList();
    final minVersion = [2, 4, 0];

    for (var i = 0; i < 3; i++) {
      final current = parts[i];
      if (current > minVersion[i]) return true;
      if (current < minVersion[i]) return false;
    }

    return true;
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
        header: const PageHeader(title: Text('设备升级')),
        content: const Center(
          child: Text('请先连接设备'),
        ),
      );
    }

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('设备升级'),
        commandBar: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isUpgrading)
              const ProgressRing(
                strokeWidth: 2.0,
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
              // 错误和成功消息
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: InfoBar(
                    title: const Text('错误'),
                    content: Text(_errorMessage!),
                    severity: InfoBarSeverity.error,
                  ),
                ),
              if (_successMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: InfoBar(
                    title: const Text('成功'),
                    content: Text(_successMessage!),
                    severity: InfoBarSeverity.success,
                  ),
                ),

              // 引导加载程序升级
              _buildSection(
                title: '引导加载程序升级',
                icon: FluentIcons.update_restore,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前版本: ${device.blVer ?? "未知"}'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextBox(
                            placeholder: '选择引导加载程序固件',
                            controller:
                                TextEditingController(text: _bootloaderFwPath),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Button(
                            child: const Text('选择固件'),
                            onPressed: _selectBootloaderFirmware,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isUpgrading) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ProgressBar(
                              value: _upgradeProgress,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(_upgradeProgress).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        child: const Text('升级引导加载程序'),
                        onPressed: _isAppVersionSupported(device.swVer)
                            ? _upgradeBootloader
                            : null,
                      ),
                    ),
                    if (!_isAppVersionSupported(device.swVer))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '需要应用版本 2.4.0 或更高版本',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 应用升级
              _buildSection(
                title: '应用升级',
                icon: FluentIcons.update_restore,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前版本: ${device.swVer ?? "未知"}'),
                    const SizedBox(height: 16),
                    if (!_inBootloader)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          child: const Text('进入引导加载程序'),
                          onPressed: _enterBootloader,
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextBox(
                              placeholder: '选择应用固件',
                              controller:
                                  TextEditingController(text: _appFwPath),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Button(
                              child: const Text('选择固件'),
                              onPressed: _selectAppFirmware,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          child: const Text('升级应用'),
                          onPressed: _upgradeApp,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 下载固件
              _buildSection(
                title: '下载固件',
                icon: FluentIcons.download,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    child: const Text('从 GitHub 下载固件'),
                    onPressed: _downloadFirmware,
                  ),
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
}

import 'screens/home.dart';
import 'screens/settings.dart';
import 'screens/about.dart';
import 'screens/device_settings.dart';
import 'screens/device_upgrade.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as flutter_acrylic;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:window_manager/window_manager.dart';

import 'theme.dart';
import 'package:hslynk/src/rust/frb_generated.dart';
import 'src/device/device_manager.dart';

const String appTitle = 'HSLynk';

/// Checks if the current environment is a desktop environment.
bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

/// 应用程序的主入口函数
void main() async {
  await RustLib.init();

  // 确保Flutter绑定初始化完成
  WidgetsFlutterBinding.ensureInitialized();

  // 如果不是运行在web、Windows或Android平台上,
  // 则加载系统主题的强调色
  if (!kIsWeb &&
      [
        TargetPlatform.windows,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform)) {
    SystemTheme.accentColor.load();
  }

  // 如果是桌面平台,进行窗口相关的初始化设置
  if (isDesktop) {
    // 初始化亚克力效果
    await flutter_acrylic.Window.initialize();

    // Windows平台特定设置 - 隐藏默认窗口控件
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await flutter_acrylic.Window.hideWindowControls();
    }

    // 初始化窗口管理器
    await WindowManager.instance.ensureInitialized();

    // 等待窗口准备就绪后进行配置
    windowManager.waitUntilReadyToShow().then((_) async {
      // 设置标题栏样式为隐藏,并且不显示窗口按钮
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      // 设置窗口最小尺寸
      await windowManager.setMinimumSize(const Size(500, 600));
      // 显示窗口
      await windowManager.show();
      // 设置防止窗口被关闭
      await windowManager.setPreventClose(true);
      // 在任务栏显示窗口
      await windowManager.setSkipTaskbar(false);
    });
  }

  // 运行Flutter应用
  runApp(const MyApp());
}

final _appTheme = AppTheme();

/// MyApp类是应用程序的根组件
/// 它负责设置应用的主题、路由和整体结构
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用ChangeNotifierProvider来提供主题数据
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appTheme),
        ChangeNotifierProvider(create: (_) => DeviceManager()),
      ],
      builder: (context, child) {
        // 监听主题变化
        final appTheme = context.watch<AppTheme>();
        // 返回FluentApp作为应用根组件
        return FluentApp.router(
          title: appTitle, // 设置应用标题
          themeMode: appTheme.mode, // 设置主题模式(亮色/暗色/系统)
          debugShowCheckedModeBanner: false, // 隐藏调试标签
          color: appTheme.color, // 设置应用主色调
          // 配置暗色主题
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen(context) ? 2.0 : 0.0, // 根据屏幕大小调整焦点效果
            ),
          ),
          // 配置默认主题(亮色)
          theme: FluentThemeData(
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen(context) ? 2.0 : 0.0,
            ),
          ),
          locale: appTheme.locale, // 设置语言区域
          // 构建应用的基础布局结构
          builder: (context, child) {
            return Directionality(
              textDirection: appTheme.textDirection, // 设置文字方向(LTR/RTL)
              child: NavigationPaneTheme(
                data: NavigationPaneThemeData(
                  // 根据窗口效果设置导航栏背景色
                  backgroundColor: appTheme.windowEffect !=
                          flutter_acrylic.WindowEffect.disabled
                      ? Colors.transparent
                      : null,
                ),
                child: child!,
              ),
            );
          },
          // 配置路由相关
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          routeInformationProvider: router.routeInformationProvider,
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.child,
    required this.shellContext,
  });

  final Widget child;
  final BuildContext? shellContext;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// _MyHomePageState 类继承自 MyHomePage 的 State,并混入 WindowListener 用于处理窗口事件
class _MyHomePageState extends State<MyHomePage> with WindowListener {
  bool value = false;

  // 导航视图的全局 Key
  final viewKey = GlobalKey(debugLabel: 'Navigation View Key');

  // 定义导航栏的主要项目列表
  late final List<NavigationPaneItem> originalItems = [
    // 首页导航项
    PaneItem(
      key: const ValueKey('/'),
      icon: const Icon(FluentIcons.home),
      title: const Text('首页'),
      body: const SizedBox.shrink(),
    ),
    // 设备设置导航项
    PaneItem(
      key: const ValueKey('/device_settings'),
      icon: const Icon(FluentIcons.repair),
      title: const Text('设备设置'),
      body: const SizedBox.shrink(),
      onTap: () {
        final deviceManager = context.read<DeviceManager>();
        final connectedDevice = deviceManager.connectedDeviceSn;
        if (connectedDevice != null) {
          context.go('/device_settings?sn=$connectedDevice');
        } else {
          context.go('/device_settings');
        }
      },
    ),
    // 设备升级导航项
    PaneItem(
      key: const ValueKey('/device_upgrade'),
      icon: const Icon(FluentIcons.update_restore),
      title: const Text('设备升级'),
      body: const SizedBox.shrink(),
      onTap: () {
        final deviceManager = context.read<DeviceManager>();
        final connectedDevice = deviceManager.connectedDeviceSn;
        if (connectedDevice != null) {
          context.go('/device_upgrade?sn=$connectedDevice');
        } else {
          context.go('/device_upgrade');
        }
      },
    ),
  ].map<NavigationPaneItem>((e) {
    // 构建导航项的辅助函数
    PaneItem buildPaneItem(PaneItem item) {
      return PaneItem(
        key: item.key,
        icon: item.icon,
        title: item.title,
        body: item.body,
        onTap: () {
          // 获取导航路径并执行导航
          final path = (item.key as ValueKey).value;
          if (GoRouterState.of(context).uri.toString() != path) {
            context.go(path);
          }
          item.onTap?.call();
        },
      );
    }

    // 处理可展开的导航项
    if (e is PaneItemExpander) {
      return PaneItemExpander(
        key: e.key,
        icon: e.icon,
        title: e.title,
        body: e.body,
        items: e.items.map((item) {
          if (item is PaneItem) return buildPaneItem(item);
          return item;
        }).toList(),
      );
    }
    return buildPaneItem(e);
  }).toList();

  // 定义导航栏底部项目列表
  late final List<NavigationPaneItem> footerItems = [
    PaneItemSeparator(), // 分隔线
    // 设置页面导航项
    PaneItem(
      key: const ValueKey('/settings'),
      icon: const Icon(FluentIcons.settings),
      title: const Text('设置'),
      body: const SizedBox.shrink(),
      onTap: () {
        if (GoRouterState.of(context).uri.toString() != '/settings') {
          context.go('/settings');
        }
      },
    ),
    // 关于页面导航项
    PaneItem(
      key: const ValueKey('/about'),
      icon: const Icon(FluentIcons.info),
      title: const Text('关于'),
      body: const SizedBox.shrink(),
      onTap: () {
        if (GoRouterState.of(context).uri.toString() != '/about') {
          context.go('/about');
        }
      },
    ),
  ];

  @override
  void initState() {
    // 初始化时添加窗口监听器
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    // 销毁时移除窗口监听器
    windowManager.removeListener(this);
    super.dispose();
  }

  // 计算当前选中的导航项索引
  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final path = location.split('?')[0]; // 移除查询参数部分

    // 在主要项目列表中查找
    int indexOriginal = originalItems
        .where((item) => item.key != null)
        .toList()
        .indexWhere((item) {
      final itemPath = (item.key as ValueKey).value.toString();
      return itemPath == path;
    });

    if (indexOriginal == -1) {
      // 在底部项目列表中查找
      int indexFooter = footerItems
          .where((element) => element.key != null)
          .toList()
          .indexWhere((element) {
        final itemPath = (element.key as ValueKey).value.toString();
        return itemPath == path;
      });
      if (indexFooter == -1) {
        return 0;
      }
      return originalItems
              .where((element) => element.key != null)
              .toList()
              .length +
          indexFooter;
    } else {
      return indexOriginal;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取主题相关配置
    final appTheme = context.watch<AppTheme>();

    // 处理路由状态更新
    if (widget.shellContext != null) {
      if (router.canPop() == false) {
        setState(() {});
      }
    }

    // 构建导航视图
    return NavigationView(
      key: viewKey,
      // 构建应用栏
      appBar: NavigationAppBar(
        automaticallyImplyLeading: false,
        // 构建标题
        title: () {
          if (kIsWeb) {
            return const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            );
          }
          return const DragToMoveArea(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            ),
          );
        }(),
        // 构建操作区域
        actions: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          // 设备连接状态指示器
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8.0),
              child: Consumer<DeviceManager>(
                builder: (context, deviceManager, child) {
                  final connectedDevice = deviceManager.connectedDeviceSn;
                  final isConnected = connectedDevice != null;
                  final device = isConnected 
                      ? deviceManager.availableDevices.firstWhere(
                          (d) => d.sn == connectedDevice,
                          orElse: () => Device(sn: connectedDevice))
                      : null;
                  
                  return Row(
                    children: [
                      Icon(
                        isConnected ? FluentIcons.plug_connected : FluentIcons.plug_disconnected,
                        color: isConnected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConnected 
                            ? '已连接${device?.nickname != null ? " - ${device!.nickname}" : ""}'
                            : '未连接',
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // 非Web环境显示窗口控制按钮
          if (!kIsWeb) const WindowButtons(),
        ]),
      ),
      // 构建导航面板内容
      paneBodyBuilder: (item, child) {
        final name =
            item?.key is ValueKey ? (item!.key as ValueKey).value : null;
        return FocusTraversalGroup(
          key: ValueKey('body$name'),
          child: widget.child,
        );
      },
      // 构建导航面板
      pane: NavigationPane(
        selected: _calculateSelectedIndex(context),
        // 构建头部文本
        header: const SizedBox(
          height: kOneLineTileHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.0),
              child: Text(
                '菜单',
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        displayMode: appTheme.displayMode,
        // 设置导航指示器样式
        indicator: () {
          switch (appTheme.indicator) {
            case NavigationIndicators.end:
              return const EndNavigationIndicator();
            case NavigationIndicators.sticky:
              return const StickyNavigationIndicator();
          }
        }(),
        items: originalItems,
        footerItems: footerItems,
      ),
    );
  }

  // 处理窗口关闭事件
  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose && mounted) {
      showDialog(
        context: context,
        builder: (_) {
          return ContentDialog(
            title: const Text('HSLynk'),
            content: const Text('确定要退出此程序吗？'),
            actions: [
              FilledButton(
                child: const Text('是'),
                onPressed: () {
                  Navigator.pop(context);
                  windowManager.destroy();
                },
              ),
              Button(
                child: const Text('否'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    }
  }
}

/// 窗口按钮组件(最小化、最大化、关闭按钮)
class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    // 获取当前主题数据
    final FluentThemeData theme = FluentTheme.of(context);

    return SizedBox(
      width: 138, // 设置按钮组宽度
      height: 50, // 设置按钮组高度
      child: WindowCaption(
        brightness: theme.brightness, // 设置亮度主题
        backgroundColor: Colors.transparent, // 设置透明背景
      ),
    );
  }
}

/// 根导航键
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Shell导航键
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// 路由配置
final router = GoRouter(navigatorKey: rootNavigatorKey, routes: [
  /// Shell路由
  ShellRoute(
    navigatorKey: _shellNavigatorKey,

    /// 构建器函数,用于构建Shell页面
    builder: (context, state, child) {
      return MyHomePage(
        shellContext: _shellNavigatorKey.currentContext,
        child: child,
      );
    },

    /// 子路由列表
    routes: <GoRoute>[
      /// 首页路由
      GoRoute(path: '/', builder: (context, state) => const HomePage()),

      /// 设备设置路由
      GoRoute(
        path: '/device_settings',
        builder: (context, state) {
          final deviceSn = state.uri.queryParameters['sn'];
          if (deviceSn == null) {
            return const Center(child: Text('请先连接设备'));
          }
          return DeviceSettings(deviceSn: deviceSn);
        },
      ),

      /// 设备升级路由
      GoRoute(
        path: '/device_upgrade',
        builder: (context, state) {
          final deviceSn = state.uri.queryParameters['sn'];
          if (deviceSn == null) {
            return const Center(child: Text('请先连接设备'));
          }
          return DeviceUpgrade(deviceSn: deviceSn);
        },
      ),

      /// 设置页路由
      GoRoute(path: '/settings', builder: (context, state) => const Settings()),

      /// 关于页路由
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
    ],
  ),
]);

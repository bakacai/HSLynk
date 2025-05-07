// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/page.dart';

const List<String> accentColorNames = [
  '系统',
  '黄色',
  '橙色',
  '红色',
  '洋红色',
  '紫色',
  '蓝色',
  '青色',
  '绿色',
];

// 判断是否支持窗口特效
bool get kIsWindowEffectsSupported {
  return !kIsWeb &&
      [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
}

// Linux平台支持的窗口特效
const _LinuxWindowEffects = [
  WindowEffect.disabled,
  WindowEffect.transparent,
];

// Windows平台支持的窗口特效
const _WindowsWindowEffects = [
  WindowEffect.disabled,
  WindowEffect.solid,
  WindowEffect.transparent,
  WindowEffect.aero,
  WindowEffect.acrylic,
  WindowEffect.mica,
  WindowEffect.tabbed,
];

// macOS平台支持的窗口特效
const _MacosWindowEffects = [
  WindowEffect.disabled,
  WindowEffect.titlebar,
  WindowEffect.selection,
  WindowEffect.menu,
  WindowEffect.popover,
  WindowEffect.sidebar,
  WindowEffect.headerView,
  WindowEffect.sheet,
  WindowEffect.windowBackground,
  WindowEffect.hudWindow,
  WindowEffect.fullScreenUI,
  WindowEffect.toolTip,
  WindowEffect.contentBackground,
  WindowEffect.underWindowBackground,
  WindowEffect.underPageBackground,
];

// 获取当前平台支持的窗口特效列表
List<WindowEffect> get currentWindowEffects {
  if (kIsWeb) return [];

  if (defaultTargetPlatform == TargetPlatform.windows) {
    return _WindowsWindowEffects;
  } else if (defaultTargetPlatform == TargetPlatform.linux) {
    return _LinuxWindowEffects;
  } else if (defaultTargetPlatform == TargetPlatform.macOS) {
    return _MacosWindowEffects;
  }

  return [];
}

// 设置页面组件
class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

// 设置页面状态
class _SettingsState extends State<Settings> with PageMixin {
  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMediaQuery(context));
    final appTheme = context.watch<AppTheme>();
    const spacer = SizedBox(height: 10.0);
    const biggerSpacer = SizedBox(height: 40.0);
    return ScaffoldPage.scrollable(
      header: const PageHeader(title: Text('设置')),
      children: [
        Text('主题模式', style: FluentTheme.of(context).typography.subtitle),
        spacer,
        ToggleSwitch(
          content: const Text('跟随系统'),
          checked: appTheme.mode == ThemeMode.system,
          onChanged: (v) {
            if (v) {
              appTheme.mode = ThemeMode.system;
            } else {
              appTheme.mode = ThemeMode.light;
            }
          },
        ),
        const SizedBox(height: 8),
        ToggleSwitch(
          content: const Text('暗黑模式'),
          checked: FluentTheme.of(context).brightness.isDark,
          onChanged: appTheme.mode == ThemeMode.system
              ? null
              : (v) {
                  if (v) {
                    appTheme.mode = ThemeMode.dark;
                  } else {
                    appTheme.mode = ThemeMode.light;
                  }
                },
        ),
        biggerSpacer,
        Text('强调色', style: FluentTheme.of(context).typography.subtitle),
        spacer,
        Wrap(children: [
          Tooltip(
            message: accentColorNames[0],
            child: _buildColorBlock(appTheme, systemAccentColor),
          ),
          ...List.generate(Colors.accentColors.length, (index) {
            final color = Colors.accentColors[index];
            return Tooltip(
              message: accentColorNames[index + 1],
              child: _buildColorBlock(appTheme, color),
            );
          }),
        ]),
        if (kIsWindowEffectsSupported) ...[
          biggerSpacer,
          Text(
            '窗口透明度',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          description(
            content: Text(
              '运行平台: ${defaultTargetPlatform.toString().replaceAll('TargetPlatform.', '')}',
            ),
          ),
          spacer,
          ...List.generate(currentWindowEffects.length, (index) {
            final mode = currentWindowEffects[index];
            return Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8.0),
              child: RadioButton(
                checked: appTheme.windowEffect == mode,
                onChanged: (value) async {
                  if (value) {
                    await Window.setEffect(
                      effect: mode,
                      color: [
                        WindowEffect.solid,
                        WindowEffect.acrylic,
                      ].contains(mode)
                          ? FluentTheme.of(context)
                              .micaBackgroundColor
                              .withValues(alpha: 0.05)
                          : Colors.transparent,
                      dark: FluentTheme.of(context).brightness.isDark,
                    );
                    if (mounted) {
                      appTheme.windowEffect = mode;
                    }
                  }
                },
                content: Text(
                  mode.toString().replaceAll('WindowEffect.', ''),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  // 构建颜色块组件
  Widget _buildColorBlock(AppTheme appTheme, AccentColor color) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Button(
        onPressed: () {
          appTheme.color = color;
        },
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.isPressed) {
              return color.light;
            } else if (states.isHovered) {
              return color.lighter;
            }
            return color;
          }),
        ),
        child: Container(
          height: 40,
          width: 40,
          alignment: AlignmentDirectional.center,
          child: appTheme.color == color
              ? Icon(
                  FluentIcons.check_mark,
                  color: color.basedOnLuminance(),
                  size: 22.0,
                )
              : null,
        ),
      ),
    );
  }
}

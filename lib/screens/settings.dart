// ignore_for_file: constant_identifier_names

import 'package:fluent_ui/fluent_ui.dart';
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

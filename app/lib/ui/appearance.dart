import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/appearance.dart';

String appearanceLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};
IconData appearanceIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.desktop_windows_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

class AppearanceButton extends ConsumerWidget {
  const AppearanceButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider).value ?? ThemeMode.system;
    return PopupMenuButton<ThemeMode>(
      tooltip: '外观：${appearanceLabel(mode)}',
      initialValue: mode,
      icon: Icon(appearanceIcon(mode)),
      onSelected: (value) async {
        final saved = await ref.read(appearanceProvider.notifier).change(value);
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('外观已切换，但暂时无法保存选择')));
        }
      },
      itemBuilder: (context) => [
        for (final value in ThemeMode.values)
          CheckedPopupMenuItem(
            value: value,
            checked: value == mode,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(appearanceIcon(value), size: 20),
                const SizedBox(width: 12),
                Text(appearanceLabel(value)),
              ],
            ),
          ),
      ],
    );
  }
}

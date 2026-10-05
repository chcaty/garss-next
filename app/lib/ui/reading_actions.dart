import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/library.dart';

void toggleSavedWithFeedback(
  BuildContext context,
  WidgetRef ref,
  Article article,
) {
  final removed = ref.read(libraryProvider).requireValue.saved[article.id];
  final controller = ref.read(libraryProvider.notifier);
  controller.toggleSaved(article);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(removed == null ? '已加入稍后读' : '已移出稍后读'),
      duration: const Duration(seconds: 8),
      action: removed == null
          ? null
          : SnackBarAction(
              label: '撤销',
              onPressed: () => controller.restoreSaved(removed),
            ),
    ),
  );
}

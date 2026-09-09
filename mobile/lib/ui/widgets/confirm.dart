import 'package:flutter/material.dart';

import '../../theme/funkin_theme.dart';

/// Ask before something that cannot be taken back.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: FunkinColors.panel,
      title: Text(title),
      content: Text(message, style: const TextStyle(color: FunkinColors.muted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: destructive ? Colors.redAccent : FunkinColors.pink,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return answer ?? false;
}

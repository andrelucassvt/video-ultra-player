import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

Future<void> showAspectRatioSheet(
  BuildContext context,
  EditorController controller,
) {
  const options = [
    _AspectRatioOption(
      '9:16',
      Icons.stay_current_portrait,
      OutputAspectRatio.ratio9x16,
    ),
    _AspectRatioOption('1:1', Icons.crop_square, OutputAspectRatio.ratio1x1),
    _AspectRatioOption(
      '16:9',
      Icons.stay_current_landscape,
      OutputAspectRatio.ratio16x9,
    ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: editorSurface,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Proporção',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              for (final option in options)
                ListTile(
                  leading: Icon(option.icon),
                  title: Text(option.label),
                  trailing: controller.aspectRatio == option.value
                      ? const Icon(Icons.check, color: editorAccent)
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(controller.setAspectRatio(option.value));
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _AspectRatioOption {
  const _AspectRatioOption(this.label, this.icon, this.value);

  final String label;
  final IconData icon;
  final OutputAspectRatio value;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

Future<void> showSpeedSheet(BuildContext context, EditorController controller) {
  var speed = controller.selectedClipSpeed;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: editorSurface,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Velocidade',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '${speed.toStringAsFixed(2)}x',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Slider(
                    value: speed,
                    min: 0.5,
                    max: 2,
                    divisions: 6,
                    label: '${speed.toStringAsFixed(2)}x',
                    onChanged: (value) => setState(() => speed = value),
                    onChangeEnd: (value) {
                      unawaited(controller.setSelectedClipSpeed(value));
                    },
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      for (final preset in const [0.5, 1.0, 1.5, 2.0])
                        ChoiceChip(
                          label: Text('${preset.toStringAsFixed(1)}x'),
                          selected: speed == preset,
                          onSelected: (_) {
                            setState(() => speed = preset);
                            unawaited(controller.setSelectedClipSpeed(preset));
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

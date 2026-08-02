import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

Future<void> showImageDurationSheet(
  BuildContext context,
  EditorController controller,
) {
  final minSeconds =
      controller.minImageClipDuration.inMilliseconds /
      Duration.millisecondsPerSecond;
  final maxSeconds =
      controller.maxImageClipDuration.inMilliseconds /
      Duration.millisecondsPerSecond;
  var seconds =
      (controller.selectedClipImageDuration.inMilliseconds /
              Duration.millisecondsPerSecond)
          .clamp(minSeconds, maxSeconds);

  return showModalBottomSheet<void>(
    context: context,
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
                    'Duração da imagem',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Quanto tempo a imagem fica em cena antes do próximo clip.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: editorAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: editorAccent.withValues(alpha: 0.34),
                        ),
                      ),
                      child: Text(
                        '${seconds.toStringAsFixed(1)}s',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: editorAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: seconds,
                    min: minSeconds,
                    max: maxSeconds,
                    divisions: (maxSeconds - minSeconds).round(),
                    label: '${seconds.toStringAsFixed(1)}s',
                    onChanged: (value) => setState(() => seconds = value),
                    onChangeEnd: (value) {
                      unawaited(
                        controller.setSelectedClipImageDuration(
                          Duration(
                            milliseconds:
                                (value * Duration.millisecondsPerSecond)
                                    .round(),
                          ),
                        ),
                      );
                    },
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

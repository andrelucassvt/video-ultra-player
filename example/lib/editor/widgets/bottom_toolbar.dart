import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/aspect_ratio_sheet.dart';
import 'package:video_ultra_player_example/editor/widgets/speed_sheet.dart';

class BottomToolbar extends StatelessWidget {
  const BottomToolbar({
    super.key,
    required this.controller,
    required this.state,
  });

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  Widget build(BuildContext context) {
    final hasTimeline = controller.hasTimeline && controller.clips.isNotEmpty;
    final canSplit =
        hasTimeline &&
        state.localPosition > Duration.zero &&
        state.clipIndex >= 0 &&
        state.clipIndex < controller.clips.length;
    final canEditSelected = hasTimeline && controller.hasSelectedClip;
    final canRemove = canEditSelected && controller.clips.length > 1;

    return Container(
      height: 82,
      color: editorBackground,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ToolbarAction(
            icon: Icons.call_split,
            label: 'Dividir',
            enabled: canSplit,
            onPressed: () => controller.split(state),
          ),
          _ToolbarAction(
            icon: Icons.speed,
            label: 'Velocidade',
            enabled: canEditSelected,
            onPressed: () => showSpeedSheet(context, controller),
          ),
          _ToolbarAction(
            icon: Icons.aspect_ratio,
            label: 'Proporção',
            enabled: hasTimeline,
            onPressed: () => showAspectRatioSheet(context, controller),
          ),
          _ToolbarAction(
            icon: Icons.delete_outline,
            label: 'Excluir',
            enabled: canRemove,
            destructive: true,
            onPressed: controller.removeSelected,
          ),
        ],
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : null;

    return SizedBox(
      width: 82,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(foregroundColor: color),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

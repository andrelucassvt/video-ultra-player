import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

Future<void> showAspectRatioSheet(
  BuildContext context,
  EditorController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: editorSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            18 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SingleChildScrollView(
            child: _AspectRatioSheetContent(controller: controller),
          ),
        ),
      );
    },
  );
}

class _AspectRatioSheetContent extends StatefulWidget {
  const _AspectRatioSheetContent({required this.controller});

  final EditorController controller;

  @override
  State<_AspectRatioSheetContent> createState() =>
      _AspectRatioSheetContentState();
}

class _AspectRatioSheetContentState extends State<_AspectRatioSheetContent> {
  static const _options = [
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
    _AspectRatioOption('Personalizado', Icons.tune, OutputAspectRatio.custom),
  ];
  static const _frameRates = [24, 30, 60];

  late final TextEditingController _widthController = TextEditingController(
    text: '${widget.controller.customWidth}',
  );
  late final TextEditingController _heightController = TextEditingController(
    text: '${widget.controller.customHeight}',
  );

  EditorController get _controller => widget.controller;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _applyCustomSize() {
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null) return;
    unawaited(
      _controller.setCustomSize(width, height).then((_) => _syncFields()),
    );
  }

  void _swapOrientation() {
    unawaited(
      _controller
          .setCustomSize(_controller.customHeight, _controller.customWidth)
          .then((_) => _syncFields()),
    );
  }

  /// Shows the value the controller kept (rounded to even and clamped).
  void _syncFields() {
    if (!mounted) return;
    _widthController.text = '${_controller.customWidth}';
    _heightController.text = '${_controller.customHeight}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final isCustom = _controller.aspectRatio == OutputAspectRatio.custom;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Proporção', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final option in _options)
              ListTile(
                leading: Icon(option.icon),
                title: Text(option.label),
                trailing: _controller.aspectRatio == option.value
                    ? const Icon(Icons.check, color: editorAccent)
                    : null,
                onTap: () {
                  if (option.value != OutputAspectRatio.custom) {
                    Navigator.of(context).pop();
                  }
                  unawaited(_controller.setAspectRatio(option.value));
                },
              ),
            if (isCustom) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DimensionField(
                      label: 'Largura',
                      controller: _widthController,
                      onSubmitted: _applyCustomSize,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Inverter orientação',
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: _swapOrientation,
                  ),
                  Expanded(
                    child: _DimensionField(
                      label: 'Altura',
                      controller: _heightController,
                      onSubmitted: _applyCustomSize,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _applyCustomSize,
                  child: const Text('Aplicar'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Frame rate', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final fps in _frameRates)
                  ChoiceChip(
                    label: Text('$fps fps'),
                    selected: _controller.frameRate == fps,
                    onSelected: (_) => unawaited(_controller.setFrameRate(fps)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Aplicado ao exportar', style: textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

class _DimensionField extends StatelessWidget {
  const _DimensionField({
    required this.label,
    required this.controller,
    required this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: InputDecoration(labelText: label, suffixText: 'px'),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _AspectRatioOption {
  const _AspectRatioOption(this.label, this.icon, this.value);

  final String label;
  final IconData icon;
  final OutputAspectRatio value;
}

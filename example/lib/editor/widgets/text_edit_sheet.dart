import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';

/// Opens the bottom sheet that edits the selected text overlay.
///
/// Every control commits through [EditorController.commitTextOverlay] only on
/// commit events (submit/blur, `onChangeEnd`, selection) — never on every
/// tick, because native text mutations are expensive (Android rebuilds the
/// Media3 composition).
Future<void> showTextEditSheet(
  BuildContext context,
  EditorController controller,
  TimelinePlayerState state,
) {
  final overlay = controller.selectedTextOverlay;
  if (overlay == null) {
    return Future<void>.value();
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: editorSurface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return TextEditSheet(controller: controller, state: state);
    },
  );
}

/// Predefined color swatches for text and background.
const List<Color> textSwatchColors = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFD64545),
  Color(0xFF4C8DFF),
  Color(0xFF2AA79B),
  Color(0xFF3FBF3F),
  Color(0xFFFFA500),
  Color(0xFFB34CFF),
  Color(0xFFFF5FA2),
  Color(0xFF8C6A3D),
];

/// System font names offered in the sheet. The native layer resolves them and
/// falls back when a name is not available on the platform.
const List<String> textFontOptions = <String>[
  'Helvetica',
  'Arial',
  'Courier',
  'Times New Roman',
  'sans-serif',
  'serif',
  'monospace',
];

class TextEditSheet extends StatefulWidget {
  const TextEditSheet({
    super.key,
    required this.controller,
    required this.state,
  });

  final EditorController controller;
  final TimelinePlayerState state;

  @override
  State<TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<TextEditSheet> {
  late TimelineTextOverlay _draft;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.selectedTextOverlay!;
    _textController = TextEditingController(text: _draft.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.state.totalDuration.inMilliseconds;
    final maxWindowMs = totalMs > 0 ? totalMs : 1;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Texto', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: _textController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Conteúdo do texto',
                filled: true,
                fillColor: editorBackground,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: editorLine),
                ),
              ),
              onSubmitted: (value) => _commit(_draft.copyWith(text: value)),
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Cor do texto'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in textSwatchColors)
                  _ColorSwatch(
                    color: color,
                    selected: _draft.color == color.toARGB32(),
                    onTap: () =>
                        _commit(_draft.copyWith(color: color.toARGB32())),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Fundo'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in textSwatchColors.take(8))
                  _ColorSwatch(
                    color: color,
                    selected: _draft.backgroundColor == color.toARGB32(),
                    onTap: () => _commit(
                      _draft.copyWith(backgroundColor: color.toARGB32()),
                    ),
                  ),
                _ColorSwatch(
                  color: const Color(0x00000000),
                  selected: _draft.backgroundColor == 0x00000000,
                  onTap: () =>
                      _commit(_draft.copyWith(backgroundColor: 0x00000000)),
                  isNone: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Tamanho'),
            Slider(
              value: _draft.fontSize,
              min: 0.02,
              max: 0.30,
              label: '${(_draft.fontSize * 100).round()}%',
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(fontSize: value)),
              onChangeEnd: (value) => _commit(_draft.copyWith(fontSize: value)),
            ),
            _sectionTitle(context, 'Opacidade'),
            Slider(
              value: _draft.opacity,
              min: 0,
              max: 1,
              label: '${(_draft.opacity * 100).round()}%',
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(opacity: value)),
              onChangeEnd: (value) => _commit(_draft.copyWith(opacity: value)),
            ),
            _sectionTitle(context, 'Rotação'),
            Slider(
              value: _draft.rotationDegrees,
              min: -180,
              max: 180,
              label: '${_draft.rotationDegrees.round()}°',
              onChanged: (value) => setState(
                () => _draft = _draft.copyWith(rotationDegrees: value),
              ),
              onChangeEnd: (value) =>
                  _commit(_draft.copyWith(rotationDegrees: value)),
            ),
            const SizedBox(height: 14),
            _sectionTitle(context, 'Alinhamento'),
            const SizedBox(height: 8),
            SegmentedButton<TimelineTextAlign>(
              segments: const <ButtonSegment<TimelineTextAlign>>[
                ButtonSegment(
                  value: TimelineTextAlign.left,
                  icon: Icon(Icons.format_align_left),
                ),
                ButtonSegment(
                  value: TimelineTextAlign.center,
                  icon: Icon(Icons.format_align_center),
                ),
                ButtonSegment(
                  value: TimelineTextAlign.right,
                  icon: Icon(Icons.format_align_right),
                ),
              ],
              selected: <TimelineTextAlign>{_draft.textAlign},
              onSelectionChanged: (selection) {
                _commit(_draft.copyWith(textAlign: selection.first));
              },
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Fonte'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _draft.fontFamily,
              decoration: const InputDecoration(
                filled: true,
                fillColor: editorBackground,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: editorLine),
                ),
              ),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Padrão'),
                ),
                for (final font in textFontOptions)
                  DropdownMenuItem<String?>(value: font, child: Text(font)),
              ],
              onChanged: (value) => _commit(_draft.copyWith(fontFamily: value)),
            ),
            const SizedBox(height: 18),
            _sectionTitle(context, 'Janela de tempo'),
            RangeSlider(
              values: RangeValues(
                _draft.start.inMilliseconds.clamp(0, maxWindowMs).toDouble(),
                _draft.end.inMilliseconds.clamp(0, maxWindowMs).toDouble(),
              ),
              min: 0,
              max: maxWindowMs.toDouble(),
              labels: RangeLabels(
                _formatMs(
                  _draft.start.inMilliseconds.clamp(0, maxWindowMs).toInt(),
                ),
                _formatMs(
                  _draft.end.inMilliseconds.clamp(0, maxWindowMs).toInt(),
                ),
              ),
              onChanged: (values) => setState(() {
                _draft = _draft.copyWith(
                  start: Duration(milliseconds: values.start.round()),
                  end: Duration(milliseconds: values.end.round()),
                );
              }),
              onChangeEnd: (values) => _commit(
                _draft.copyWith(
                  start: Duration(milliseconds: values.start.round()),
                  end: Duration(milliseconds: values.end.round()),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                _commit(_draft.copyWith(text: _textController.text));
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Concluir'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                unawaited(widget.controller.removeSelectedTextOverlay());
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffd64545),
                side: const BorderSide(color: Color(0xffd64545)),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Excluir texto'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.bodySmall);
  }

  void _commit(TimelineTextOverlay next) {
    setState(() => _draft = next);
    unawaited(widget.controller.commitTextOverlay(next));
  }

  String _formatMs(int ms) {
    final minutes = (ms ~/ 60000).toString();
    final seconds = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.isNone = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isNone;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? editorAccent : editorLine,
            width: selected ? 3 : 1,
          ),
        ),
        child: isNone
            ? const Center(
                child: Icon(
                  Icons.not_interested,
                  size: 16,
                  color: editorTextMuted,
                ),
              )
            : null,
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_screen.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/media/media_clip.dart';

/// The screen shown before the editor: the user picks videos/images from the
/// device, reviews and reorders the selection, then continues into the
/// timeline editor with those clips.
class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({super.key});

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<TimelineClip> _clips = <TimelineClip>[];
  bool _picking = false;
  String? _error;

  Future<void> _addMedia() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });

    try {
      // pickMultipleMedia returns videos and images mixed, in pick order.
      final files = await _picker.pickMultipleMedia();
      if (files.isNotEmpty) {
        setState(() {
          _clips.addAll(files.map((file) => timelineClipFromPath(file.path)));
        });
      }
    } on PlatformException catch (error) {
      // 'multiple_request' just means a picker is already open; ignore it.
      if (error.code != 'multiple_request') {
        setState(() => _error = error.message ?? error.code);
      }
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeAt(int index) => setState(() => _clips.removeAt(index));

  void _openEditor() {
    if (_clips.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(clips: List<TimelineClip>.of(_clips)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: _clips.isEmpty ? _emptyState(context) : _grid(context),
            ),
            if (_error != null) _errorBar(context, _error!),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Text(
            'Selecionar mídia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          if (_clips.isNotEmpty)
            Text(
              '${_clips.length} selecionado(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.perm_media_outlined,
            size: 56,
            color: editorTextMuted,
          ),
          const SizedBox(height: 14),
          Text(
            'Nenhuma mídia selecionada',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Adicione vídeos e imagens da galeria para montar sua timeline.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _clips.length,
      itemBuilder: (context, index) {
        return _MediaTile(
          clip: _clips[index],
          order: index + 1,
          onRemove: () => _removeAt(index),
        );
      },
    );
  }

  Widget _errorBar(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.white),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      color: editorBackground,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _picking ? null : _addMedia,
              icon: _picking
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: editorAccent,
                      ),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined, size: 20),
              label: const Text('Adicionar mídia'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: editorLine),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _clips.isEmpty ? null : _openEditor,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                _clips.isEmpty ? 'Continuar' : 'Continuar (${_clips.length})',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.clip,
    required this.order,
    required this.onRemove,
  });

  final TimelineClip clip;
  final int order;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isVideo = clip.type == MediaType.video;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isVideo)
            _fallback(isVideo)
          else
            Image.file(
              File(clip.path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(isVideo),
            ),
          Positioned(
            left: 6,
            top: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: editorAccent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$order',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
          if (isVideo)
            const Positioned(
              right: 6,
              bottom: 6,
              child: Icon(Icons.videocam, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _fallback(bool isVideo) {
    return Container(
      color: editorSurfaceHigh,
      alignment: Alignment.center,
      child: Icon(
        isVideo ? Icons.movie_outlined : Icons.image_outlined,
        color: editorTextMuted,
        size: 30,
      ),
    );
  }
}

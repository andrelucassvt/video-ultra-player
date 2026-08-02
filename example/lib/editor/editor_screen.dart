import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/widgets/editor_toolbar.dart';
import 'package:video_ultra_player_example/editor/widgets/editor_top_bar.dart';
import 'package:video_ultra_player_example/editor/widgets/preview_area.dart';
import 'package:video_ultra_player_example/editor/widgets/timeline_section.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController _controller;
  bool _statusMessageScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = EditorController();
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.loadSample();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return StreamBuilder<TimelinePlayerState>(
              stream: _controller.stateStream,
              initialData: const TimelinePlayerState.initial(),
              builder: (context, snapshot) {
                _capturePlaybackError(snapshot);
                _maybeShowStatusMessage(context);
                final state =
                    snapshot.data ?? const TimelinePlayerState.initial();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: EditorTopBar(controller: _controller),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                        child: PreviewArea(
                          controller: _controller,
                          state: state,
                        ),
                      ),
                    ),
                    EditorToolbar(controller: _controller, state: state),
                    TimelineSection(controller: _controller, state: state),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _resolveError(String error) {
    if (error.contains('gallery_permission_denied')) {
      return 'Permissão da galeria negada';
    }
    if (error == editorMediaUnavailableError) {
      return 'Mídia indisponível: o arquivo não foi encontrado';
    }
    if (error == editorMediaImportFailedError) {
      return 'Falha ao importar a mídia. Tente adicionar novamente.';
    }
    return error;
  }

  String _resolveExportMessage(String message) {
    if (message == 'gallery_saved') return 'Salvo na galeria';
    return message;
  }

  void _maybeShowStatusMessage(BuildContext context) {
    if (_statusMessageScheduled) return;
    final error = _controller.error;
    final exportMessage = _controller.exportMessage;
    if (error == null && exportMessage == null) return;

    _statusMessageScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _statusMessageScheduled = false;
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_resolveError(error)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade900,
            ),
          );
        _controller.clearError();
      } else if (exportMessage != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_resolveExportMessage(exportMessage)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green.shade900,
            ),
          );
        _controller.clearExportMessage();
      }
    });
  }

  void _capturePlaybackError(AsyncSnapshot<TimelinePlayerState> snapshot) {
    if (!snapshot.hasError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final error = snapshot.error;
      if (error is PlatformException) {
        _controller.setPlaybackError(
          'Playback error [${error.code}]: ${error.message ?? "(no message)"}',
        );
      } else if (error != null) {
        _controller.setPlaybackError('Playback error: $error');
      }
    });
  }
}

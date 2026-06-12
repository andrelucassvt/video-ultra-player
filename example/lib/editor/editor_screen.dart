import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_ultra_player/video_ultra_player.dart';
import 'package:video_ultra_player_example/editor/editor_controller.dart';
import 'package:video_ultra_player_example/editor/theme/editor_theme.dart';
import 'package:video_ultra_player_example/editor/widgets/bottom_toolbar.dart';
import 'package:video_ultra_player_example/editor/widgets/editor_top_bar.dart';
import 'package:video_ultra_player_example/editor/widgets/playback_bar.dart';
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
                    PlaybackBar(controller: _controller, state: state),
                    TimelineSection(controller: _controller, state: state),
                    BottomToolbar(controller: _controller, state: state),
                    if (_controller.error != null)
                      _EditorStatusBar(
                        message: _controller.error!,
                        isError: true,
                      )
                    else if (_controller.exportMessage != null)
                      _EditorStatusBar(
                        message: _controller.exportMessage!,
                        isError: false,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
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

class _EditorStatusBar extends StatelessWidget {
  const _EditorStatusBar({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: isError ? Colors.red.shade900 : editorSurfaceHigh,
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
}

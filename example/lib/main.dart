import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_ultra_player/video_ultra_player.dart';

void main() {
  runApp(const TimelineDemoApp());
}

class TimelineDemoApp extends StatefulWidget {
  const TimelineDemoApp({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<TimelineDemoApp> createState() => _TimelineDemoAppState();
}

class _TimelineDemoAppState extends State<TimelineDemoApp> {
  final NativeTimelinePlayer _player = NativeTimelinePlayer();
  Stream<TimelinePlayerState>? _stateStream;
  int? _textureId;
  bool _loading = false;
  String? _error;
  double? _scrubValue;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _loadTimeline();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadTimeline() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final clipAPath = await _copyAssetToTempFile('assets/clip_a.mp4');
      final stillPath = await _copyAssetToTempFile('assets/still.png');
      final clipBPath = await _copyAssetToTempFile('assets/clip_b.mp4');
      final textureId = await _player.load([
        TimelineClip(
          path: clipAPath,
          type: MediaType.video,
          duration: const Duration(seconds: 2),
          scale: 1.05,
        ),
        TimelineClip(
          path: stillPath,
          type: MediaType.image,
          duration: const Duration(milliseconds: 1600),
          scale: 1.3,
        ),
        TimelineClip(
          path: clipBPath,
          type: MediaType.video,
          duration: const Duration(seconds: 2),
        ),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _textureId = textureId;
        _stateStream = _player.stateStream;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<String> _copyAssetToTempFile(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final directory = Directory(
      '${Directory.systemTemp.path}/video_ultra_player_example',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File('${directory.path}/${assetPath.split('/').last}');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff0f766e),
    );

    return MaterialApp(
      theme: ThemeData(colorScheme: colorScheme, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Native Timeline Player')),
        body: SafeArea(
          child: StreamBuilder<TimelinePlayerState>(
            stream: _stateStream,
            initialData: const TimelinePlayerState.initial(),
            builder: (context, snapshot) {
              final state =
                  snapshot.data ?? const TimelinePlayerState.initial();
              final totalMs = state.totalDuration.inMilliseconds;
              final positionMs =
                  (_scrubValue ??
                          state.globalPosition.inMilliseconds.toDouble())
                      .clamp(0, totalMs <= 0 ? 1 : totalMs)
                      .toDouble();

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Builder(
                          builder: (textureContext) {
                            return GestureDetector(
                              onPanUpdate: _textureId == null
                                  ? null
                                  : (details) {
                                      final renderBox =
                                          textureContext.findRenderObject()
                                              as RenderBox?;
                                      if (renderBox == null ||
                                          !renderBox.hasSize) {
                                        return;
                                      }

                                      final local = renderBox.globalToLocal(
                                        details.globalPosition,
                                      );
                                      final x =
                                          ((local.dx / renderBox.size.width) *
                                                      2 -
                                                  1)
                                              .clamp(-1.0, 1.0);
                                      final y =
                                          ((local.dy / renderBox.size.height) *
                                                      2 -
                                                  1)
                                              .clamp(-1.0, 1.0);
                                      _player.setClipAlignment(
                                        state.clipIndex,
                                        x,
                                        y,
                                      );
                                    },
                              child: ColoredBox(
                                color: Colors.black,
                                child: _textureId == null
                                    ? Center(
                                        child: _loading
                                            ? const CircularProgressIndicator()
                                            : const Icon(
                                                Icons.video_library_outlined,
                                                color: Colors.white70,
                                                size: 48,
                                              ),
                                      )
                                    : Texture(textureId: _textureId!),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          IconButton.filled(
                            onPressed: _textureId == null
                                ? null
                                : () {
                                    if (state.isPlaying) {
                                      _player.pause();
                                    } else {
                                      _player.play();
                                    }
                                  },
                            icon: Icon(
                              state.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Slider(
                              value: positionMs,
                              min: 0,
                              max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                              onChanged: _textureId == null
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _scrubValue = value;
                                      });
                                    },
                              onChangeEnd: _textureId == null
                                  ? null
                                  : (value) async {
                                      await _player.seekTo(
                                        Duration(milliseconds: value.round()),
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _scrubValue = null;
                                        });
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${_formatDuration(Duration(milliseconds: positionMs.round()))} / '
                            '${_formatDuration(state.totalDuration)}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _loading ? null : _loadTimeline,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _textureId == null ? 'Load timeline' : 'Reload',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Clip ${state.clipIndex + 1} of 3',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = duration.inMilliseconds.remainder(1000) ~/ 100;
    return '$minutes:$seconds.$milliseconds';
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  final ImagePicker _picker = ImagePicker();
  Stream<TimelinePlayerState>? _stateStream;
  List<TimelineClip> _clips = <TimelineClip>[];
  int? _textureId;
  int _clipCount = 3;
  String _timelineSource = 'Sample timeline';
  bool _loading = false;
  bool _exporting = false;
  bool _editBusy = false;
  String? _error;
  String? _exportPath;
  double? _scrubValue;
  OutputAspectRatio _aspectRatio = OutputAspectRatio.original;
  Stream<TimelineExportProgress>? _exportProgressStream;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _loadSampleTimeline();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadSampleTimeline() async {
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
      await _replaceTimeline([
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
      ], source: 'Sample timeline');
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

  Future<void> _pickVideosFromGallery() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final videos = await _picker.pickMultiVideo();
      if (!mounted) {
        return;
      }

      if (videos.isEmpty) {
        setState(() {
          _loading = false;
        });
        return;
      }

      await _replaceTimeline(
        videos
            .map(
              (video) => TimelineClip(path: video.path, type: MediaType.video),
            )
            .toList(growable: false),
        source: 'Gallery videos',
      );
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.message ?? error.code;
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

  Future<void> _replaceTimeline(
    List<TimelineClip> clips, {
    required String source,
  }) async {
    await _player.dispose();
    final textureId = await _player.load(clips, config: _compositionConfig);

    if (!mounted) {
      return;
    }

    setState(() {
      _textureId = textureId;
      _stateStream = _player.stateStream;
      _clips = List<TimelineClip>.of(clips);
      _clipCount = clips.length;
      _timelineSource = source;
      _scrubValue = null;
      _exportPath = null;
      _exportProgressStream = null;
      _loading = false;
    });
  }

  Future<void> _reloadCurrentTimeline() async {
    if (_loading || _exporting || _clips.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _replaceTimeline(_clips, source: _timelineSource);
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

  Future<void> _exportCurrentTimeline() async {
    if (_loading || _exporting || _textureId == null) return;

    setState(() {
      _exporting = true;
      _error = null;
      _exportPath = null;
      _exportProgressStream = null;
    });

    try {
      final directory = Directory(
        '${Directory.systemTemp.path}/video_ultra_player_example_exports',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final outputPath =
          '${directory.path}/timeline_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final exportFuture = _player.exportCurrentTimeline(outputPath: outputPath);
      setState(() {
        _exportProgressStream = _player.exportProgress;
      });
      final exportedPath = await exportFuture;

      if (!mounted) return;
      setState(() {
        _exportPath = exportedPath;
        _exporting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _exporting = false;
      });
    }
  }

  Future<void> _splitAtPlayhead(TimelinePlayerState state) async {
    if (_editBusy || _textureId == null) return;
    if (state.localPosition <= Duration.zero) return;
    setState(() => _editBusy = true);
    try {
      await _player.splitClip(state.clipIndex, state.localPosition);
      if (mounted) setState(() => _clipCount = _clipCount + 1);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editBusy = false);
    }
  }

  Future<void> _removeCurrentClip(int clipIndex, int totalClips) async {
    if (_editBusy || _textureId == null || totalClips <= 1) return;
    setState(() => _editBusy = true);
    try {
      await _player.removeClip(clipIndex);
      if (mounted) setState(() => _clipCount = totalClips - 1);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editBusy = false);
    }
  }

  Future<void> _moveClip(int fromIndex, int toIndex) async {
    if (_editBusy || _textureId == null) return;
    setState(() => _editBusy = true);
    try {
      await _player.moveClip(fromIndex, toIndex);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editBusy = false);
    }
  }

  Future<void> _trimIn(int clipIndex, Duration localPosition) async {
    if (_editBusy || _textureId == null) return;
    if (localPosition <= Duration.zero) return;
    setState(() => _editBusy = true);
    try {
      await _player.trimClip(clipIndex, trimStart: localPosition);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editBusy = false);
    }
  }

  Future<void> _trimOut(int clipIndex, Duration localPosition) async {
    if (_editBusy || _textureId == null) return;
    setState(() => _editBusy = true);
    try {
      await _player.trimClip(clipIndex, trimEnd: localPosition);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _editBusy = false);
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

  TimelineCompositionConfig get _compositionConfig {
    return TimelineCompositionConfig(aspectRatio: _aspectRatio);
  }

  double get _previewAspectRatio {
    return switch (_aspectRatio) {
      OutputAspectRatio.ratio16x9 => 16 / 9,
      OutputAspectRatio.ratio9x16 => 9 / 16,
      OutputAspectRatio.ratio1x1 => 1,
      OutputAspectRatio.original => 16 / 9,
    };
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
              if (snapshot.hasError && _error == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      final err = snapshot.error;
                      _error = err is PlatformException
                          ? 'Playback error [${err.code}]: ${err.message ?? "(no message)"}'
                          : 'Playback error (${err.runtimeType}): $err';
                    });
                  }
                });
              }
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
                        aspectRatio: _previewAspectRatio,
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
                                      if (state.clipIndex >= 0 &&
                                          state.clipIndex < _clips.length) {
                                        _clips[state.clipIndex] =
                                            _clips[state.clipIndex].copyWith(
                                              alignment: Alignment(x, y),
                                            );
                                      }
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
                      SegmentedButton<OutputAspectRatio>(
                        segments: const [
                          ButtonSegment(
                            value: OutputAspectRatio.original,
                            label: Text('Original'),
                          ),
                          ButtonSegment(
                            value: OutputAspectRatio.ratio16x9,
                            label: Text('16:9'),
                          ),
                          ButtonSegment(
                            value: OutputAspectRatio.ratio9x16,
                            label: Text('9:16'),
                          ),
                          ButtonSegment(
                            value: OutputAspectRatio.ratio1x1,
                            label: Text('1:1'),
                          ),
                        ],
                        selected: {_aspectRatio},
                        onSelectionChanged: _loading || _exporting
                            ? null
                            : (selection) {
                                setState(() {
                                  _aspectRatio = selection.first;
                                });
                                _reloadCurrentTimeline();
                              },
                      ),
                      const SizedBox(height: 8),
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
                      if (_textureId != null) ...[
                        const SizedBox(height: 8),
                        Builder(builder: (context) {
                          final liveCount = state.clipDurations.isNotEmpty
                              ? state.clipDurations.length
                              : _clipCount;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (liveCount > 1)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    for (int i = 0; i < liveCount; i++)
                                      ChoiceChip(
                                        label: Text('Clip ${i + 1}'),
                                        selected: state.clipIndex == i,
                                        onSelected: (_) {
                                          setState(() => _scrubValue = null);
                                          _player.seekToClip(i);
                                        },
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _EditButton(
                                    icon: Icons.content_cut,
                                    label: 'Split',
                                    enabled: !_editBusy &&
                                        state.localPosition > Duration.zero,
                                    onPressed: () =>
                                        _splitAtPlayhead(state),
                                  ),
                                  _EditButton(
                                    icon: Icons.delete_outline,
                                    label: 'Remove',
                                    enabled: !_editBusy && liveCount > 1,
                                    onPressed: () => _removeCurrentClip(
                                      state.clipIndex,
                                      liveCount,
                                    ),
                                  ),
                                  _EditButton(
                                    icon: Icons.arrow_back,
                                    label: 'Move ◀',
                                    enabled:
                                        !_editBusy && state.clipIndex > 0,
                                    onPressed: () => _moveClip(
                                      state.clipIndex,
                                      state.clipIndex - 1,
                                    ),
                                  ),
                                  _EditButton(
                                    icon: Icons.arrow_forward,
                                    label: 'Move ▶',
                                    enabled: !_editBusy &&
                                        state.clipIndex < liveCount - 1,
                                    onPressed: () => _moveClip(
                                      state.clipIndex,
                                      state.clipIndex + 1,
                                    ),
                                  ),
                                  _EditButton(
                                    icon: Icons.first_page,
                                    label: 'Trim in',
                                    enabled: !_editBusy &&
                                        state.localPosition > Duration.zero,
                                    onPressed: () => _trimIn(
                                      state.clipIndex,
                                      state.localPosition,
                                    ),
                                  ),
                                  _EditButton(
                                    icon: Icons.last_page,
                                    label: 'Trim out',
                                    enabled: !_editBusy,
                                    onPressed: () => _trimOut(
                                      state.clipIndex,
                                      state.localPosition,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _loading ? null : _pickVideosFromGallery,
                            icon: const Icon(Icons.video_file_outlined),
                            label: const Text('Choose videos'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _loading ? null : _loadSampleTimeline,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _textureId == null
                                  ? 'Load sample'
                                  : 'Reload sample',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _loading || _exporting || _textureId == null
                                ? null
                                : _exportCurrentTimeline,
                            icon: _exporting
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.file_download_outlined),
                            label: Text(
                              _exporting ? 'Exporting' : 'Export MP4',
                            ),
                          ),
                          Text(
                            'Clip ${state.clipIndex + 1} of ${state.clipDurations.isNotEmpty ? state.clipDurations.length : _clipCount} - $_timelineSource',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      if (_exportPath != null) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          'Exported to $_exportPath',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (_exporting || _exportProgressStream != null) ...[
                        const SizedBox(height: 12),
                        StreamBuilder<TimelineExportProgress>(
                          stream: _exportProgressStream,
                          initialData: const TimelineExportProgress.idle(),
                          builder: (context, exportSnapshot) {
                            final exportProgress =
                                exportSnapshot.data ??
                                const TimelineExportProgress.idle();
                            final percent = (exportProgress.progress * 100)
                                .round();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LinearProgressIndicator(
                                  value:
                                      exportProgress.state ==
                                          TimelineExportState.idle
                                      ? null
                                      : exportProgress.progress,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Export ${exportProgress.state.name} - $percent%',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
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

class _EditButton extends StatelessWidget {
  const _EditButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}

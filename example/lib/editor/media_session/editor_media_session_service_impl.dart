import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:video_ultra_player_example/editor/media_session/editor_media_session_service.dart';

typedef SupportDirectoryProvider = Future<Directory> Function();

/// [EditorMediaSessionService] that copies media into Application Support and
/// never deletes paths outside the directory it controls.
class EditorMediaSessionServiceImpl implements EditorMediaSessionService {
  EditorMediaSessionServiceImpl({SupportDirectoryProvider? supportDirectoryProvider})
    : _supportDirectoryProvider =
          supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const _sessionsDirectoryName = 'video_ultra_player_example_editor_sessions';

  final SupportDirectoryProvider _supportDirectoryProvider;
  Future<void> _operationTail = Future<void>.value();
  Directory? _sessionDirectory;
  bool _preparedSessionsRoot = false;

  @override
  Future<String> importFile(String sourcePath) {
    return _enqueue(() async {
      final source = File(sourcePath);
      if (!await source.exists()) {
        throw FileSystemException('Source media does not exist.', sourcePath);
      }

      final sessionDirectory = await _ensureSessionDirectory();
      final mediaDirectory = await sessionDirectory.createTemp('media_');
      final sourceSegments = source.uri.pathSegments;
      final sourceName = sourceSegments.isEmpty ? '' : sourceSegments.last;
      final fileName = sourceName.isEmpty ? 'media' : sourceName;
      final destination = File('${mediaDirectory.path}/$fileName');

      try {
        final copied = await source.copy(destination.path);
        return copied.path;
      } catch (_) {
        if (await mediaDirectory.exists()) {
          await mediaDirectory.delete(recursive: true);
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> releaseFile(String ownedPath) {
    return _enqueue(() async {
      final sessionDirectory = _sessionDirectory;
      if (sessionDirectory == null) return;

      final sessionPrefix =
          '${sessionDirectory.absolute.path}${Platform.pathSeparator}';
      final target = File(ownedPath).absolute;
      if (!target.path.startsWith(sessionPrefix)) return;

      if (await target.exists()) {
        await target.delete();
      }

      final mediaDirectory = target.parent;
      if (await mediaDirectory.exists() &&
          mediaDirectory.path != sessionDirectory.path &&
          await mediaDirectory.list().isEmpty) {
        await mediaDirectory.delete();
      }
    });
  }

  @override
  Future<void> clearSession() {
    return _enqueue(() async {
      final sessionDirectory = _sessionDirectory;
      _sessionDirectory = null;
      if (sessionDirectory != null && await sessionDirectory.exists()) {
        await sessionDirectory.delete(recursive: true);
      }
    });
  }

  Future<Directory> _ensureSessionDirectory() async {
    final currentSession = _sessionDirectory;
    if (currentSession != null && await currentSession.exists()) {
      return currentSession;
    }

    final supportDirectory = await _supportDirectoryProvider();
    final sessionsRoot = Directory(
      '${supportDirectory.path}/$_sessionsDirectoryName',
    );

    if (!_preparedSessionsRoot) {
      if (await sessionsRoot.exists()) {
        await sessionsRoot.delete(recursive: true);
      }
      _preparedSessionsRoot = true;
    }

    if (!await sessionsRoot.exists()) {
      await sessionsRoot.create(recursive: true);
    }

    final sessionDirectory = await sessionsRoot.createTemp('session_');
    _sessionDirectory = sessionDirectory;
    return sessionDirectory;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) async {
    final previousOperation = _operationTail;
    final releaseNextOperation = Completer<void>();
    _operationTail = releaseNextOperation.future;

    await previousOperation;
    try {
      return await operation();
    } finally {
      releaseNextOperation.complete();
    }
  }
}

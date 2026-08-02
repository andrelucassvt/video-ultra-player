import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_ultra_player_example/editor/media_session/editor_media_session_service_impl.dart';

void main() {
  late Directory sandbox;
  late Directory supportDirectory;
  late EditorMediaSessionServiceImpl service;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'editor_media_session_test_',
    );
    supportDirectory = Directory('${sandbox.path}/support');
    await supportDirectory.create(recursive: true);
    service = EditorMediaSessionServiceImpl(
      supportDirectoryProvider: () async => supportDirectory,
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('importFile copies source into the owned session', () async {
    final source = File('${sandbox.path}/timeline_source.mp4');
    await source.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

    final ownedPath = await service.importFile(source.path);

    expect(ownedPath, isNot(source.path));
    expect(ownedPath, startsWith(supportDirectory.path));
    expect(ownedPath, endsWith('.mp4'));
    expect(await File(ownedPath).readAsBytes(), <int>[1, 2, 3, 4]);
  });

  test('releaseFile deletes only owned media', () async {
    final source = File('${sandbox.path}/selected.png');
    await source.writeAsBytes(<int>[9, 8, 7], flush: true);
    final ownedPath = await service.importFile(source.path);

    await service.releaseFile(source.path);
    await service.releaseFile(ownedPath);

    expect(await source.exists(), isTrue);
    expect(await File(ownedPath).exists(), isFalse);
  });

  test('clearSession removes imported files', () async {
    final source = File('${sandbox.path}/selected.mov');
    await source.writeAsBytes(<int>[5, 6], flush: true);
    final ownedPath = await service.importFile(source.path);

    await service.clearSession();

    expect(await File(ownedPath).exists(), isFalse);
  });

  test('first import of a new service wipes stale sessions', () async {
    final source = File('${sandbox.path}/selected.mp4');
    await source.writeAsBytes(<int>[5, 6], flush: true);
    final ownedPath = await service.importFile(source.path);

    final secondService = EditorMediaSessionServiceImpl(
      supportDirectoryProvider: () async => supportDirectory,
    );
    await secondService.importFile(source.path);

    expect(await File(ownedPath).exists(), isFalse);
  });
}

# Flow: Native Timeline Player

> **Resumo:** Carrega uma timeline de clipes de vídeo/imagem, cria uma composição nativa única por plataforma, renderiza tudo em uma única `Texture` Flutter e exporta a união final como MP4 com a mesma configuração de transição, aspect ratio, trilha de áudio externa opcional, histórico de edição e progresso real de exportação.

## Visão Geral

O fluxo começa no app de exemplo em `example/lib/main.dart`, que inicializa `EditorScreen`. A tela delega o estado operacional para `example/lib/editor/editor_controller.dart`: carregar os assets empacotados do demo, abrir a galeria com `image_picker`, importar áudio com `file_picker`, controlar seleção, exportar e aplicar edições. Em todos os caminhos, o controller monta uma lista de `TimelineClip` com paths locais, guarda essa lista em `_clips` e chama `NativeTimelinePlayer.load` com a `TimelineCompositionConfig` atual.

No Dart do plugin, `NativeTimelinePlayer` valida que há ao menos um clipe, serializa cada `TimelineClip` com `toJson()`, serializa a `TimelineCompositionConfig` e delega para `VideoUltraPlayerPlatform.instance`. A implementação padrão é `MethodChannelVideoUltraPlayer`, que envia comandos pelo `MethodChannel('video_ultra_player/timeline_player')`, recebe estados pelo `EventChannel('video_ultra_player/timeline_player/events')` e recebe progresso de exportação pelo `EventChannel('video_ultra_player/timeline_player/export')`. Para exportação, o mesmo method channel envia `exportTimeline` com `clips`, `outputPath` opcional e `config`, enquanto `exportProgress` emite `TimelineExportProgress` até `completed` ou `failed`.

No iOS, `VideoUltraPlayerPlugin` recebe `load`, valida argumentos, faz parse da config, cria um `TimelinePlayerController`, monta a timeline com `AVMutableComposition` em `TimelineComposition`, registra uma `TimelineTexture` no `FlutterTextureRegistry` e devolve o `textureId`. A composição alterna duas tracks de vídeo/áudio quando há crossfade, aplica `setOpacityRamp` e `setVolumeRamp` nas janelas de overlap, calcula `renderSize` pelo preset de aspect ratio e recalcula `totalDuration` subtraindo os overlaps. A textura usa `AVPlayerItemVideoOutput` com `CADisplayLink` para avisar o Flutter quando há novo frame. Para `exportTimeline`, o plugin monta uma nova `TimelineComposition`, aplica a mesma `AVVideoComposition`/`AVAudioMix` usada no preview, faz polling de `AVAssetExportSession.progress` e grava o MP4 com `AVAssetExportSession`.

No Android, `VideoUltraPlayerPlugin` recebe os mesmos comandos, faz parse da config, cria um `TimelineCompositionController`, monta uma `Composition` com `CompositionPlayer`, registra um `SurfaceTexture` do Flutter com o tamanho do preset, entrega esse `Surface` ao player e devolve o `textureId`. A composição usa uma sequência Media3 por clipe com gaps para posicionar os starts com overlap e um `VideoCompositorSettings` custom para variar o alpha por timestamp durante o crossfade; o aspect ratio usa `Presentation.createForWidthAndHeight(..., LAYOUT_SCALE_TO_FIT_WITH_CROP)` por clipe. O estado é emitido periodicamente a cada ~33 ms pelo `EventChannel`. Para `exportTimeline`, o plugin cria um `TimelineCompositionExporter`, reutiliza os helpers de parsing/duração/composição, faz polling de `Transformer.getProgress(ProgressHolder)` e chama Media3 `Transformer` para gerar o arquivo final.

O resultado final no Flutter é renderizado em `PreviewArea` com `Texture(textureId: controller.textureId)`. A UI do exemplo usa o `stateStream` para atualizar playback, timeline, playhead, botões de undo/redo e duração; a interação volta pela API pública com `play`, `pause`, `seekTo`, `seekToClip`, `setClipAlignment`, `trimClip`, `moveClip`, `splitClip`, `removeClip`, `setClipSpeed`, `setAudioTrack`, `removeAudioTrack`, `exportCurrentTimeline` e `dispose`.

Undo/redo é mantido no nativo como snapshots do edit-model, não como replay de comandos no Dart. Antes de cada mutação de edição, iOS e Android salvam a lista de clipes atual e a trilha de áudio externa ativa em uma pilha de undo; ao desfazer/refazer, restauram o snapshot, recompõem uma vez preservando `textureId`, fazem seek com clamp para uma posição válida e emitem `canUndo`/`canRedo` no `stateStream`.

## Passo a Passo

1. **App de exemplo** — `example/lib/main.dart` → `TimelineEditorApp`
   Configura `MaterialApp` com o tema escuro do editor e abre `EditorScreen`.

2. **App de exemplo / assets** — `example/lib/editor/editor_controller.dart` → `loadSample` / `_copyAssetToTempFile`
   Copia `assets/clip_a.mp4`, `assets/still.png` e `assets/clip_b.mp4` para `Directory.systemTemp`, porque a camada nativa trabalha com paths de arquivo locais.

3. **App de exemplo / galeria** — `example/lib/editor/widgets/editor_top_bar.dart` → menu do título → `EditorController.pickVideos`
   Abre o seletor de vídeos com `ImagePicker.pickMultiVideo()`. Se o usuário escolher vídeos, converte cada `XFile.path` em `TimelineClip(type: MediaType.video)`.

4. **App de exemplo / controller** — `example/lib/editor/editor_controller.dart` → `replaceTimeline`
   Descarta a timeline anterior com `_player.dispose()`, carrega a nova lista de clipes com `_player.load(clips, config: compositionConfig)`, reaplica áudio externo quando necessário, guarda `_clips`, atualiza `textureId`, `stateStream`, origem da timeline e cache de thumbnails.

5. **App de exemplo / preview** — `example/lib/editor/widgets/preview_area.dart` → `GestureDetector.onPanUpdate`
   Converte a posição do arrasto para `x/y` em `[-1, 1]`, atualiza o `TimelineClip` correspondente em `_clips` e chama `_player.setClipAlignment(...)` para alterar o preview nativo.

6. **App de exemplo / exportação** — `example/lib/editor/widgets/editor_top_bar.dart` → `EditorController.export`
   Cria um path em `Directory.systemTemp`, chama `_player.exportCurrentTimeline(outputPath: outputPath)`, assina `_player.exportProgress` enquanto o export está ativo e exibe o path final quando a exportação termina.

6.1. **App de exemplo / config** — `example/lib/editor/widgets/editor_top_bar.dart` + `aspect_ratio_sheet.dart`
   O menu de resolução altera `baseWidth` (720p/1080p) e o sheet de proporção altera `OutputAspectRatio` (9:16, 1:1, 16:9). Mudanças recarregam o preview com a mesma config usada no export atual.

7. **API Dart** — `lib/src/models/timeline_clip.dart` → `TimelineClip.toJson`
   Serializa cada clipe como `path`, `type`, `durationMs`, `alignment.x/y` e `scale`.

7.1. **API Dart / config** — `lib/src/models/timeline_composition_config.dart` → `TimelineCompositionConfig.toJson`
   Serializa `transitionDurationMs`, `aspectRatio` (`ratio16x9`, `ratio9x16`, `ratio1x1`, `original`) e `baseWidth`. O construtor rejeita duração negativa e `baseWidth <= 0`.

7.2. **API Dart / progresso** — `lib/src/models/timeline_export_progress.dart` → `TimelineExportProgress.fromMap`
   Converte eventos nativos `{progress, state}` em `progress` clampado entre 0 e 1 e `TimelineExportState`.

8. **API Dart / preview** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.load`
   Rejeita timeline vazia com `ArgumentError`, serializa a config default ou recebida, chama `_platform.load(...)`, armazena o `textureId` e reseta o cache de `stateStream`.

9. **API Dart / exportação** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.exportTimeline`
   Rejeita timeline vazia com `ArgumentError`, impede exportações simultâneas, serializa os clipes e a config e chama `_platform.exportTimeline(...)`. Não exige que `load()` tenha sido chamado. Enquanto o export está ativo, `exportProgress` expõe o stream de progresso.

10. **Platform Interface** — `lib/video_ultra_player_platform_interface.dart` → `VideoUltraPlayerPlatform.instance`
   Mantém o contrato abstrato da API nativa e usa `MethodChannelVideoUltraPlayer` como implementação padrão.

11. **Method Channel Dart / preview** — `lib/video_ultra_player_method_channel.dart` → `MethodChannelVideoUltraPlayer.load`
   Envia `load` pelo channel `video_ultra_player/timeline_player` com `{'clips': clips, 'config': config}` e espera um `int` como `textureId`.

12. **Method Channel Dart / exportação** — `lib/video_ultra_player_method_channel.dart` → `MethodChannelVideoUltraPlayer.exportTimeline`
    Envia `exportTimeline` pelo mesmo channel com `clips`, `outputPath` e `config`, e espera uma `String` com o path do arquivo exportado. `exportProgress()` assina `video_ultra_player/timeline_player/export`.

13. **iOS nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `register(with:)`
   Registra o `FlutterMethodChannel`, o `FlutterEventChannel` e mantém acesso ao `FlutterTextureRegistry`.

14. **iOS nativo / preview** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `load`
   Valida `clips`, converte os mapas em `TimelineClipDescriptor`, cria `TimelinePlayerController`, armazena o controller por `textureId` e retorna esse id ao Dart.

15. **iOS nativo / exportação** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `exportTimeline`
    Valida `clips`, resolve `outputPath` ou cria um arquivo temporário, monta `TimelineComposition.buildExportAsset`, configura `AVAssetExportSession` e retorna o path quando a exportação completa.

16. **iOS composição** — `ios/Classes/TimelineComposition.swift` → `TimelineComposition.build`
    Cria um `AVMutableComposition`, adiciona duas tracks de vídeo e duas de áudio, insere clipes alternados com overlap calculado a partir de `transitionDurationMs`, aplica `renderSize` pelo preset e cria a tabela de `TimelineSegment` usada para calcular estado e duração total.

17. **iOS composição / exportação** — `ios/Classes/TimelineComposition.swift` → `TimelineComposition.buildExportAsset`
    Reutiliza `build(clips:)` e devolve o `AVAsset` da composição junto com a `AVVideoComposition` para o `AVAssetExportSession`.

18. **iOS composição** — `ios/Classes/TimelineComposition.swift` → `makeVideoComposition` / `makeAudioMix`
    Gera instruções single-layer fora dos overlaps e instruções double-layer nas transições, com opacity ramp 1→0 no clipe que sai e 0→1 no clipe que entra. O áudio usa `AVMutableAudioMixInputParameters` com volume ramp equivalente.

19. **iOS textura** — `ios/Classes/TimelineTexture.swift` → `TimelineTexture`
    Conecta `AVPlayerItemVideoOutput` ao `AVPlayerItem`, registra frames com `CADisplayLink` e fornece `CVPixelBuffer` por `copyPixelBuffer()`.

20. **Android nativo** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `onAttachedToEngine`
    Registra `MethodChannel`, `EventChannel`, `applicationContext` e `TextureRegistry`.

21. **Android nativo / preview** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `load`
    Valida a lista `clips`, cria `TimelineCompositionController`, chama `controller.load(clips)`, armazena o controller por `textureId` e retorna esse id ao Dart.

22. **Android composição / parsing** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `parseTimelineClips`
    Converte os mapas em `TimelineClip`, resolve duração de vídeos com `MediaMetadataRetriever`, aplica fallback de imagem e devolve clipes com `resolvedDurationMs`.

23. **Android composição** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `buildTimelineComposition`
    Cria `MediaItem`/`EditedMediaItem` para cada clipe, usa `setImageDurationMs` para imagens, força `durationUs`, aplica crop/alinhamento e `Presentation` por clipe, monta uma `EditedMediaItemSequence` por clipe com gaps de posicionamento e usa `TimelineVideoCompositorSettings` para alpha ramp durante overlaps.

24. **Android composição / preview** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `load`
    Converte os mapas em `TimelineClip`, resolve durações, cria um `SurfaceTexture` Flutter, cria um `Surface`, instancia `CompositionPlayer`, configura a superfície de vídeo e prepara a composição.

25. **Android nativo / exportação** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `exportTimeline`
    Valida `clips`, cria um `TimelineCompositionExporter`, mantém o exporter em `activeExporters` e retorna sucesso/erro de forma assíncrona ao Flutter.

26. **Android exportação** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `TimelineCompositionExporter.export`
    Resolve o arquivo de saída, parseia clipes/config, chama `buildTimelineComposition(...)`, inicia `Transformer.start(composition, outputPath)`, faz polling de `Transformer.getProgress(ProgressHolder)` e devolve o path no listener `onCompleted`.

27. **Render Flutter** — `example/lib/editor/widgets/preview_area.dart` → `Texture`
    Quando `controller.textureId` existe, renderiza `Texture(textureId: controller.textureId!)` dentro de um `AspectRatio` derivado de `OutputAspectRatio`; quando não existe, mostra o placeholder do editor.

28. **Estado Dart** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.stateStream`
    Exige que `load` já tenha completado, pede `_platform.stateStream(textureId)` e converte o stream para broadcast.

29. **Estado nativo iOS** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController.emitState`
    Usa `AVPlayer.currentTime()`, cruza a posição com `TimelineComposition.playbackState`, e emite `globalPosition`, `clipIndex`, `localPosition`, `isPlaying` e `totalDuration`.

30. **Estado nativo Android** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `emitState`
    Usa `CompositionPlayer.currentPosition`, calcula o índice do segmento atual e emite o mesmo mapa de estado pelo `EventChannel`.

31. **Controles Dart / playback** — `example/lib/editor/widgets/playback_bar.dart`
    Alterna `play/pause`, formata `posição / total` e chama `controller.undo()` / `controller.redo()` quando as flags nativas e o histórico local do editor permitem.

31.1. **Controles Dart / timeline** — `example/lib/editor/widgets/timeline_section.dart`
    Desenha régua, playhead, faixa de clipes e faixa de áudio com uma coordenada única (`pixelsPerSecond`). Scrub pelo playhead usa seek throttled; toque na régua faz seek direto.

31.2. **Controles Dart / clipes** — `example/lib/editor/widgets/clip_strip.dart` + `clip_trim_handles.dart`
    Cada clipe tem largura proporcional à duração resolvida, thumbnails via `generateThumbnails`, seleção por toque, reordenação por long-press-drag e alças de trim que chamam `trimClip` só no release.

31.3. **Controles Dart / áudio** — `example/lib/editor/widgets/audio_track_row.dart`
    O estado vazio abre `FilePicker.pickFiles(type: FileType.audio)`; a trilha ativa chama `setAudioTrack`, permite ajustar volume no release do slider e remover com `removeAudioTrack`.

31.4. **Controles Dart / toolbar inferior** — `example/lib/editor/widgets/bottom_toolbar.dart`
    Expõe Dividir (`splitClip` no playhead), Velocidade (`setClipSpeed` via `speed_sheet.dart`), Proporção (`setAspectRatio` via `aspect_ratio_sheet.dart`) e Excluir (`removeClip` do clipe selecionado).

32. **Commands Dart** — `lib/src/native_timeline_player.dart` → `play`, `pause`, `seekTo`, `seekToClip`, `setVolume`, `setClipAlignment`, `undo`, `redo`, `dispose`
    Todos exigem `textureId` carregado; `setVolume` valida faixa `0.0..1.0`; `seekToClip(clipIndex)` faz seek ao início do clipe `clipIndex` resolvido no nativo; `undo`/`redo` delegam para o histórico nativo; `dispose` limpa `textureId`, stream local e chama a plataforma.

32.1. **Trilha de áudio Dart** — `lib/src/models/audio_track.dart` + `lib/src/native_timeline_player.dart` → `AudioTrack.toJson` / `setAudioTrack` / `removeAudioTrack`
   `AudioTrack` serializa `path`, `offsetMs`, `volume`, `trimStartMs`, `trimEndMs`, `fadeInMs` e `fadeOutMs`. `NativeTimelinePlayer.setAudioTrack` e `removeAudioTrack` exigem `load()` concluído e delegam para a platform interface usando o `textureId` ativo.

32.2. **Trilha de áudio channel** — `lib/video_ultra_player_method_channel.dart` → `setAudioTrack` / `removeAudioTrack`
   Envia `setAudioTrack` com `{textureId, track}` e `removeAudioTrack` com `{textureId}` pelo channel `video_ultra_player/timeline_player`.

32.3. **Histórico Dart** — `lib/src/models/timeline_player_state.dart` + `lib/src/models/edit_history_state.dart`
   `TimelinePlayerState.fromMap` lê `canUndo` e `canRedo` dos eventos nativos para a UI habilitar botões. `EditHistoryState` é o model simples do mesmo par de flags quando o app consumidor quiser tratar o histórico separadamente.

33. **Commands nativos** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`
    Cada comando busca o controller pelo `textureId` e delega para o controller nativo correspondente. `seekToClip` usa `TimelineComposition.startTime(forClipIndex:)` no iOS e `segments.getOrNull(clipIndex)?.startMs` no Android; índice inválido é no-op seguro em ambas as plataformas.

33.1. **Trilha de áudio iOS** — `ios/Classes/VideoUltraPlayerPlugin.swift` / `ios/Classes/TimelineComposition.swift` → `setAudioTrack` / `removeAudioTrack` / `makeAudioMix`
   O plugin converte o mapa em `AudioTrackDescriptor`, guarda a trilha no controller e reconstrói o `AVPlayerItem` preservando textura e posição. `TimelineComposition` insere uma track de áudio separada no `offset`, aplica `trimStart/trimEnd`, volume e ramps lineares de fade, e reutiliza o mesmo `AVAudioMix` no export atual.

33.2. **Trilha de áudio Android** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` / `TimelineCompositionController.kt` → `setAudioTrack` / `removeAudioTrack` / `audioSequenceFor`
   O plugin envia o mapa para o controller, que resolve a duração do arquivo, guarda uma única `AudioTrackDescriptor` e reconstrói a `Composition` no commit. A trilha externa entra como sequência Media3 de áudio com gap inicial para `offset`, clipping para `trim`, `GainProcessor` para volume/fades lineares e é incluída em `exportCurrentTimeline`.

33.3. **Histórico nativo** — `ios/Classes/TimelineEditModel.swift` + `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt`
   Cada plataforma mantém pilhas limitadas de snapshots (`clips` + `audioTrack`). Mutações como trim, split, insert, remove, move, replace, velocidade, alinhamento e trilha de áudio chamam `pushSnapshot` antes de alterar o modelo; `undo`/`redo` movem snapshots entre as pilhas e recompõem o preview.

34. **Limpeza** — `ios/Classes/VideoUltraPlayerPlugin.swift` / `TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`
    `dispose` pausa/release o player, remove observer/timer, unregister/release da textura e limpa recursos temporários. No Android, `onDetachedFromEngine` também cancela exporters ativos.

### Caminhos alternativos

- **Timeline vazia no Dart:** `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.load` e `NativeTimelinePlayer.exportTimeline` lançam `ArgumentError` antes de chamar a plataforma.
- **Comando antes do load:** `lib/src/native_timeline_player.dart` → `_requireTextureId` lança `StateError`.
- **Volume fora de faixa:** `lib/src/native_timeline_player.dart` → `setVolume` lança `RangeError`.
- **Seleção cancelada na galeria:** `example/lib/editor/editor_controller.dart` → `pickVideos` mantém a timeline atual e apenas encerra o estado de loading.
- **Erro do picker:** `example/lib/editor/editor_controller.dart` → `pickVideos` captura `PlatformException` e exibe a mensagem em `_error`.
- **Seleção cancelada no áudio:** `example/lib/editor/editor_controller.dart` → `addAudioTrack` mantém a timeline atual quando o `file_picker` retorna sem path.
- **Falha de exportação no example:** `example/lib/editor/editor_controller.dart` → `export` captura exceções, encerra `_exporting` e exibe a mensagem em `_error`.
- **Argumentos inválidos no iOS:** `ios/Classes/VideoUltraPlayerPlugin.swift` → `load`, `textureId(from:result:)` e `onListen` retornam `FlutterError` com `invalid_arguments` ou `invalid_clip`.
- **Argumentos inválidos no Android:** `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `load`, `withController`, `seekTo`, `setVolume` e `setClipAlignment` retornam `result.error(...)`.
- **Controller não encontrado:** `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` retornam erro `not_found` quando o `textureId` não existe mais.
- **Falha de composição:** iOS retorna `FlutterError(code: "load_failed")` em `ios/Classes/VideoUltraPlayerPlugin.swift`; Android retorna `result.error("load_failed", ...)` em `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`.
- **Falha de exportação nativa:** iOS retorna `FlutterError(code: "export_failed")` em `ios/Classes/VideoUltraPlayerPlugin.swift`; Android retorna `result.error("export_failed", ...)` em `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`.
- **Erro de playback Android:** `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `Player.Listener.onPlayerError` propaga `playback_error` pelo `EventChannel`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública Dart | `lib/video_ultra_player.dart` | Exporta `NativeTimelinePlayer`, `TimelineClip`, `MediaType`, `TimelinePlayerState`, `TimelineCompositionConfig` e `TimelineExportProgress`. |
| Modelo Dart | `lib/src/models/timeline_clip.dart` | Define clipes de timeline e serialização para o contrato nativo. |
| Modelo Dart | `lib/src/models/audio_track.dart` | Define a trilha de áudio externa única, com offset, volume, trim e fades opcionais. |
| Modelo Dart | `lib/src/models/edit_history_state.dart` | Define as flags `canUndo`/`canRedo` do histórico de edição. |
| Modelo Dart | `lib/src/models/timeline_composition_config.dart` | Define transição global, preset de aspect ratio e serialização da config de composição. |
| Modelo Dart | `lib/src/models/timeline_export_progress.dart` | Define estados de exportação e parsing dos eventos de progresso. |
| Modelo Dart | `lib/src/models/timeline_player_state.dart` | Define o estado emitido pelo player e converte mapas nativos em `Duration`/campos Dart. |
| API Dart | `lib/src/native_timeline_player.dart` | Orquestra load/export/comandos, guarda `textureId`, valida uso antes do load e expõe `stateStream`. |
| Platform interface | `lib/video_ultra_player_platform_interface.dart` | Contrato abstrato de preview, exportação, comandos e stream entre API Dart e implementação de plataforma. |
| Channel Dart | `lib/video_ultra_player_method_channel.dart` | Implementa o contrato com `MethodChannel`, `EventChannel` e retorno de path em `exportTimeline`. |
| iOS plugin | `ios/Classes/VideoUltraPlayerPlugin.swift` | Registra channels, gerencia controllers por textura, recebe comandos, exporta MP4 e emite estados. |
| iOS histórico | `ios/Classes/TimelineEditModel.swift` | Mantém pilhas de snapshots para undo/redo do edit-model nativo. |
| iOS composição | `ios/Classes/TimelineComposition.swift` | Monta `AVMutableComposition`, `AVVideoComposition`, segmentos, duração total, fallback de imagem e asset exportável. |
| iOS textura | `ios/Classes/TimelineTexture.swift` | Liga `AVPlayerItemVideoOutput` ao `FlutterTexture` e notifica frames disponíveis. |
| Android plugin | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | Registra channels, gerencia controllers por textura, exporters ativos e valida argumentos. |
| Android histórico | `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt` | Mantém pilhas de snapshots para undo/redo do edit-model nativo. |
| Android composição | `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | Monta `CompositionPlayer`, `Transformer`, `Composition`, `SurfaceTexture`, efeitos, estado, exportação e dispose. |
| Exemplo | `example/lib/main.dart` | Inicializa o `TimelineEditorApp` e aponta para `EditorScreen`. |
| Exemplo / controller | `example/lib/editor/editor_controller.dart` | Encapsula `NativeTimelinePlayer`, clipes, textura, stream de estado, export, thumbnails, áudio externo, seleção, seek throttled e ações de edição da UI. |
| Exemplo / tela | `example/lib/editor/editor_screen.dart` | Monta a tela do editor com top bar, preview, playback bar, timeline e toolbar inferior. |
| Exemplo / tema | `example/lib/editor/theme/editor_theme.dart` | Define tema escuro, surfaces, accent amarelo e estilos base do editor. |
| Exemplo / top bar | `example/lib/editor/widgets/editor_top_bar.dart` | Exibe reset/menu de origem, resolução e exportação com progresso. |
| Exemplo / preview | `example/lib/editor/widgets/preview_area.dart` | Renderiza a `Texture` do player, placeholder e pan/crop por gesto. |
| Exemplo / playback | `example/lib/editor/widgets/playback_bar.dart` | Controla play/pause, tempo e undo/redo. |
| Exemplo / timeline | `example/lib/editor/widgets/timeline_section.dart` | Coordena régua, playhead, faixa de clipes, faixa de áudio, scroll e zoom. |
| Exemplo / timeline | `example/lib/editor/widgets/timeline_ruler.dart` | Widget da régua interativa de segundos. |
| Exemplo / timeline | `example/lib/editor/widgets/timeline_ruler_painter.dart` | `CustomPainter` das marcações e labels de segundos. |
| Exemplo / timeline | `example/lib/editor/widgets/timeline_playhead.dart` | Agulha arrastável do playhead. |
| Exemplo / timeline | `example/lib/editor/widgets/clip_strip.dart` | Renderiza clipes com largura proporcional, thumbnails, seleção e reordenação. |
| Exemplo / timeline | `example/lib/editor/widgets/clip_trim_handles.dart` | Renderiza alças de trim e badge de duração do clipe selecionado. |
| Exemplo / áudio | `example/lib/editor/widgets/audio_track_row.dart` | Importa áudio, mostra trilha ativa, volume e remover. |
| Exemplo / toolbar | `example/lib/editor/widgets/bottom_toolbar.dart` | Expõe Dividir, Velocidade, Proporção e Excluir. |
| Exemplo / toolbar | `example/lib/editor/widgets/speed_sheet.dart` | Ajusta velocidade do clipe selecionado. |
| Exemplo / toolbar | `example/lib/editor/widgets/aspect_ratio_sheet.dart` | Ajusta proporção de saída do preview/export. |
| Assets do exemplo | `example/assets/clip_a.mp4` | Primeiro clipe de vídeo do demo. |
| Assets do exemplo | `example/assets/still.png` | Clipe de imagem do demo. |
| Assets do exemplo | `example/assets/clip_b.mp4` | Segundo clipe de vídeo do demo. |
| Configuração package | `pubspec.yaml` | Declara o plugin Flutter e as plataformas Android/iOS. |
| Configuração example | `example/pubspec.yaml` | Declara dependência local no plugin e assets usados pelo demo. |
| Configuração iOS example | `example/ios/Runner/Info.plist` | Declara `NSPhotoLibraryUsageDescription` para permitir seleção de vídeos da biblioteca no iOS. |
| Configuração Android | `android/build.gradle.kts` | Declara dependências Media3 `common`, `effect` e `transformer` na versão `1.10.1`. |
| Configuração iOS example | `example/ios/Podfile` | Configura CocoaPods para o app de exemplo Flutter/iOS. |
| Testes Dart | `test/native_timeline_player_test.dart` | Cobre API pública, serialização, exportação, validações, commands, textureId e stream. |
| Testes Dart | `test/video_ultra_player_method_channel_test.dart` | Cobre payloads enviados pelo `MethodChannel`, exportação e conversão de estado. |
| Testes Android | `android/src/test/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPluginTest.kt` | Cobre fallback `notImplemented` para método desconhecido. |
| Testes example | `example/test/widget_test.dart` | Cobre renderização inicial dos controles do demo. |
| Testes example | `example/integration_test/plugin_integration_test.dart` | Cobre conversão básica de `TimelinePlayerState.fromMap`. |
| Testes iOS example | `example/ios/RunnerTests/RunnerTests.swift` | Cobre fallback `FlutterMethodNotImplemented` para método desconhecido. |

## Regras de Negócio Relevantes

- **A timeline precisa ter pelo menos um clipe** — `lib/src/native_timeline_player.dart`: `load` e `exportTimeline` lançam `ArgumentError` se a lista estiver vazia; Android também usa `require(rawClips.isNotEmpty())`.
- **Comandos exigem player carregado** — `lib/src/native_timeline_player.dart`: `_requireTextureId` impede `play`, `pause`, `seekTo`, `seekToClip`, `setVolume`, `setClipAlignment` e `stateStream` antes do `load`.
- **Exportação não exige preview carregado** — `lib/src/native_timeline_player.dart`: `exportTimeline` trabalha só com a lista de `TimelineClip` recebida e não chama `_requireTextureId`.
- **Um export ativo por player** — `lib/src/native_timeline_player.dart`: `exportTimeline` lança `StateError` se outra exportação ainda está em andamento; `exportProgress` só pode ser obtido durante um export ativo.
- **Config de composição é global** — `lib/src/models/timeline_composition_config.dart`: `transitionDuration`, `aspectRatio` e `baseWidth` valem para a composição inteira e são enviados tanto em `load` quanto em `exportTimeline`.
- **Transições encurtam a duração total** — `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: cada overlap subtrai tempo da soma sequencial; o estado usa os segmentos com overlap para calcular `totalDuration`, `clipIndex` e `localPosition`.
- **Aspect ratio usa cover-crop** — iOS aplica scale-to-fill/crop no transform da composição; Android usa `Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP`.
- **Volume aceito só entre 0 e 1** — `lib/src/native_timeline_player.dart`: valida no Dart; iOS e Android também fazem clamp no nativo.
- **Trilha de áudio externa é única** — `lib/src/models/audio_track.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: só há um `AudioTrack` ativo por player; `setAudioTrack` substitui o anterior e `removeAudioTrack` volta para o áudio embutido dos clipes.
- **Trilha de áudio exige preview carregado** — `lib/src/native_timeline_player.dart`: `setAudioTrack` e `removeAudioTrack` usam `_requireTextureId`, então só funcionam após `load`.
- **Export atual inclui áudio externo** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: `exportCurrentTimeline` usa o estado nativo atual, incluindo a trilha externa ativa. `exportTimeline(clips)` continua exportando apenas a lista de clipes recebida.
- **Undo/redo é snapshot nativo** — `ios/Classes/TimelineEditModel.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt`: o histórico guarda metadados de edição (`clips` com trim, speed, alignment, transição e trilha de áudio), não mídia nem comandos Dart.
- **Redo é limpo em nova edição** — `ios/Classes/TimelineEditModel.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt`: qualquer novo `pushSnapshot` limpa a pilha de redo.
- **Histórico é limitado** — `ios/Classes/TimelineEditModel.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt`: as pilhas mantêm no máximo 50 snapshots para limitar uso de memória.
- **`TimelineClip.scale` precisa ser positivo** — `lib/src/models/timeline_clip.dart`: assert no construtor; nativos também aplicam mínimo defensivo (`0.01`).
- **Estado sempre trafega em milissegundos** — `lib/src/models/timeline_player_state.dart`, `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: nativo emite números e Dart converte para `Duration`.
- **O `textureId` é o identificador do controller nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`: controllers ficam em mapas por textura.
- **Imagens têm duração explícita** — `example/lib/editor/editor_controller.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: imagens usam duração informada ou fallback de 2 segundos.
- **Vídeos com duração informada podem ser cortados** — `ios/Classes/TimelineComposition.swift`: para vídeo, `duration(for:asset:)` usa `CMTimeMinimum` entre duração pedida e duração do asset.
- **Pan/crop trabalha em coordenadas normalizadas** — `example/lib/editor/widgets/preview_area.dart`, `example/lib/editor/editor_controller.dart`, `lib/src/models/timeline_clip.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: `x/y` são tratados no intervalo `[-1, 1]`.
- **iOS usa fallback para imagem** — `ios/Classes/TimelineComposition.swift`: imagem é convertida em MP4 temporário com `AVAssetWriter` antes de entrar na composição.
- **Example mantém pan/crop para exportação** — `example/lib/editor/editor_controller.dart`: o arrasto no vídeo também atualiza `_clips[state.clipIndex]`; `exportCurrentTimeline` exporta o estado nativo atual, preservando alinhamento, trim, velocidade e áudio.
- **UI de edição commita no release** — `example/lib/editor/widgets/timeline_section.dart`, `clip_trim_handles.dart`, `audio_track_row.dart` e `speed_sheet.dart`: scrub usa seek throttled; trim, volume e velocidade chamam mutações nativas no fim do gesto/slider.
- **Android reconstrói a composição para pan/crop** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: efeitos Media3 são imutáveis, então `setClipAlignment` chama `setComposition(buildTimelineComposition(clips), positionMs)`.
- **Exportação Android mantém exporter vivo até finalizar** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`: `activeExporters` retém `TimelineCompositionExporter` e cancela exporters no detach do engine.
- **Dispose remove recursos nativos** — `ios/Classes/VideoUltraPlayerPlugin.swift`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: unregister/release da textura, player e recursos temporários.

## Dependências Externas

- **Flutter plugin channels** — `MethodChannel`, `EventChannel` e `Texture`/`TextureRegistry` são usados para comunicação e render.
- **image_picker 1.2.2** — usado no app de exemplo para selecionar múltiplos vídeos da galeria com `pickMultiVideo()`.
- **file_picker 11.0.2** — usado no app de exemplo para selecionar uma trilha de áudio externa.
- **iOS AVFoundation** — `AVMutableComposition`, `AVVideoComposition`, `AVPlayer`, `AVPlayerItemVideoOutput`, `AVAssetWriter` e `AVAssetExportSession`.
- **Android Media3 1.10.1** — `androidx.media3:media3-common`, `androidx.media3:media3-effect`, `androidx.media3:media3-transformer`, `CompositionPlayer`, `Transformer` e `GainProcessor`.
- **Android platform media APIs** — `MediaMetadataRetriever`, `Surface`, `SurfaceTexture`.
- **CocoaPods no example iOS** — `example/ios/Podfile` integra Flutter, `integration_test` e o plugin local.

## Observações

- O projeto é um Flutter plugin, então o fluxo não passa por Cubit, Repository ou DataSource. A fronteira arquitetural principal é API Dart → platform interface → channels → código nativo.
- O documento `flow/project-structure.md` ainda descreve o estado antigo de skeleton; este flow reflete o código atual depois da implementação do Native Timeline Player.
- O Android usa múltiplas sequências Media3 quando há trilha externa: a sequência principal contém os clipes e a sequência de áudio aplica `offset` por gap. `setClipAlignment`, `setClipSpeed` e `setAudioTrack` reconstróem a `Composition`; por isso a UI deve chamar esses commits apenas no release dos controles.
- O iOS usa uma única `AVMutableComposition` para preview e cria outra composição equivalente para exportação; imagens entram como vídeos temporários gerados localmente.
- `exportTimeline` retorna um path local, mas não move o arquivo para galeria/fotos; o app consumidor decide onde salvar/compartilhar o MP4 final.
- O example contém textos hardcoded porque é um app de demonstração do plugin, não uma tela de produto com l10n configurado.

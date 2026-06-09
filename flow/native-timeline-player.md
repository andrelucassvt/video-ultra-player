# Flow: Native Timeline Player

> **Resumo:** Carrega uma timeline de clipes de vídeo/imagem, cria uma composição nativa única por plataforma, renderiza tudo em uma única `Texture` Flutter e exporta a união final como MP4 com a mesma configuração de transição, aspect ratio e progresso real de exportação.

## Visão Geral

O fluxo começa no app de exemplo em `example/lib/main.dart`. A tela tem dois caminhos de entrada: carregar os assets empacotados do demo ou abrir a galeria com `image_picker` para escolher vídeos do dispositivo. Em ambos os casos, a tela monta uma lista de `TimelineClip` com caminhos absolutos, tipo de mídia, duração/escala quando aplicável, guarda essa lista em `_clips` e chama `NativeTimelinePlayer.load` com a `TimelineCompositionConfig` atual.

No Dart do plugin, `NativeTimelinePlayer` valida que há ao menos um clipe, serializa cada `TimelineClip` com `toJson()`, serializa a `TimelineCompositionConfig` e delega para `VideoUltraPlayerPlatform.instance`. A implementação padrão é `MethodChannelVideoUltraPlayer`, que envia comandos pelo `MethodChannel('video_ultra_player/timeline_player')`, recebe estados pelo `EventChannel('video_ultra_player/timeline_player/events')` e recebe progresso de exportação pelo `EventChannel('video_ultra_player/timeline_player/export')`. Para exportação, o mesmo method channel envia `exportTimeline` com `clips`, `outputPath` opcional e `config`, enquanto `exportProgress` emite `TimelineExportProgress` até `completed` ou `failed`.

No iOS, `VideoUltraPlayerPlugin` recebe `load`, valida argumentos, faz parse da config, cria um `TimelinePlayerController`, monta a timeline com `AVMutableComposition` em `TimelineComposition`, registra uma `TimelineTexture` no `FlutterTextureRegistry` e devolve o `textureId`. A composição alterna duas tracks de vídeo/áudio quando há crossfade, aplica `setOpacityRamp` e `setVolumeRamp` nas janelas de overlap, calcula `renderSize` pelo preset de aspect ratio e recalcula `totalDuration` subtraindo os overlaps. A textura usa `AVPlayerItemVideoOutput` com `CADisplayLink` para avisar o Flutter quando há novo frame. Para `exportTimeline`, o plugin monta uma nova `TimelineComposition`, aplica a mesma `AVVideoComposition`/`AVAudioMix` usada no preview, faz polling de `AVAssetExportSession.progress` e grava o MP4 com `AVAssetExportSession`.

No Android, `VideoUltraPlayerPlugin` recebe os mesmos comandos, faz parse da config, cria um `TimelineCompositionController`, monta uma `Composition` com `CompositionPlayer`, registra um `SurfaceTexture` do Flutter com o tamanho do preset, entrega esse `Surface` ao player e devolve o `textureId`. A composição usa uma sequência Media3 por clipe com gaps para posicionar os starts com overlap e um `VideoCompositorSettings` custom para variar o alpha por timestamp durante o crossfade; o aspect ratio usa `Presentation.createForWidthAndHeight(..., LAYOUT_SCALE_TO_FIT_WITH_CROP)` por clipe. O estado é emitido periodicamente a cada ~33 ms pelo `EventChannel`. Para `exportTimeline`, o plugin cria um `TimelineCompositionExporter`, reutiliza os helpers de parsing/duração/composição, faz polling de `Transformer.getProgress(ProgressHolder)` e chama Media3 `Transformer` para gerar o arquivo final.

O resultado final no Flutter é renderizado com `Texture(textureId: player.textureId)`. A UI do exemplo usa o `stateStream` para atualizar posição, clipe atual e estado de reprodução, e envia `play`, `pause`, `seekTo`, `setVolume`, `setClipAlignment`, `exportTimeline` e `dispose` de volta pela mesma API pública.

## Passo a Passo

1. **App de exemplo** — `example/lib/main.dart` → `_TimelineDemoAppState.initState`
   Quando `autoLoad` é verdadeiro, chama `_loadSampleTimeline()` ao iniciar a tela.

2. **App de exemplo / assets** — `example/lib/main.dart` → `_loadSampleTimeline` / `_copyAssetToTempFile`
   Copia `assets/clip_a.mp4`, `assets/still.png` e `assets/clip_b.mp4` para `Directory.systemTemp`, porque a camada nativa trabalha com paths de arquivo locais.

3. **App de exemplo / galeria** — `example/lib/main.dart` → `_pickVideosFromGallery`
   Abre o seletor de vídeos com `ImagePicker.pickMultiVideo()`. Se o usuário escolher vídeos, converte cada `XFile.path` em `TimelineClip(type: MediaType.video)`.

4. **App de exemplo** — `example/lib/main.dart` → `_replaceTimeline`
   Descarta a timeline anterior com `_player.dispose()`, carrega a nova lista de clipes com `_player.load(clips, config: _compositionConfig)`, guarda os clipes em `_clips`, atualiza `textureId`, `stateStream`, quantidade de clipes e origem da timeline.

5. **App de exemplo / pan** — `example/lib/main.dart` → `GestureDetector.onPanUpdate`
   Converte a posição do arrasto para `x/y` em `[-1, 1]`, atualiza o `TimelineClip` correspondente em `_clips` e chama `_player.setClipAlignment(...)` para alterar o preview nativo.

6. **App de exemplo / exportação** — `example/lib/main.dart` → `_exportTimeline`
   Cria um path em `Directory.systemTemp`, chama `_player.exportTimeline(_clips, outputPath: outputPath, config: _compositionConfig)`, assina `_player.exportProgress` enquanto o export está ativo e exibe o path final quando a exportação termina.

6.1. **App de exemplo / config** — `example/lib/main.dart` → controles de aspect ratio e transição
   `SegmentedButton<OutputAspectRatio>` altera o preset do output; o slider altera `transitionDuration` entre 0 e 1500 ms. Mudanças recarregam o preview com a mesma config que será usada no export.

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

27. **Render Flutter** — `example/lib/main.dart` → `Texture`
    Quando `_textureId` existe, renderiza `Texture(textureId: _textureId!)` dentro de um `AspectRatio`.

28. **Estado Dart** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.stateStream`
    Exige que `load` já tenha completado, pede `_platform.stateStream(textureId)` e converte o stream para broadcast.

29. **Estado nativo iOS** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController.emitState`
    Usa `AVPlayer.currentTime()`, cruza a posição com `TimelineComposition.playbackState`, e emite `globalPosition`, `clipIndex`, `localPosition`, `isPlaying` e `totalDuration`.

30. **Estado nativo Android** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `emitState`
    Usa `CompositionPlayer.currentPosition`, calcula o índice do segmento atual e emite o mesmo mapa de estado pelo `EventChannel`.

31. **Controles Dart** — `example/lib/main.dart` → botões, slider, pan e export
    Botão alterna `play/pause`; slider chama `seekTo(Duration)` no fim do arrasto; pan chama `setClipAlignment`; botão `Export MP4` chama `_exportTimeline`.

32. **Commands Dart** — `lib/src/native_timeline_player.dart` → `play`, `pause`, `seekTo`, `setVolume`, `setClipAlignment`, `dispose`
    Todos exigem `textureId` carregado; `setVolume` valida faixa `0.0..1.0`; `dispose` limpa `textureId`, stream local e chama a plataforma.

33. **Commands nativos** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`
    Cada comando busca o controller pelo `textureId` e delega para o controller nativo correspondente.

34. **Limpeza** — `ios/Classes/VideoUltraPlayerPlugin.swift` / `TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`
    `dispose` pausa/release o player, remove observer/timer, unregister/release da textura e limpa recursos temporários. No Android, `onDetachedFromEngine` também cancela exporters ativos.

### Caminhos alternativos

- **Timeline vazia no Dart:** `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.load` e `NativeTimelinePlayer.exportTimeline` lançam `ArgumentError` antes de chamar a plataforma.
- **Comando antes do load:** `lib/src/native_timeline_player.dart` → `_requireTextureId` lança `StateError`.
- **Volume fora de faixa:** `lib/src/native_timeline_player.dart` → `setVolume` lança `RangeError`.
- **Seleção cancelada na galeria:** `example/lib/main.dart` → `_pickVideosFromGallery` mantém a timeline atual e apenas encerra o estado de loading.
- **Erro do picker:** `example/lib/main.dart` → `_pickVideosFromGallery` captura `PlatformException` e exibe a mensagem em `_error`.
- **Falha de exportação no example:** `example/lib/main.dart` → `_exportTimeline` captura exceções, encerra `_exporting` e exibe a mensagem em `_error`.
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
| Modelo Dart | `lib/src/models/timeline_composition_config.dart` | Define transição global, preset de aspect ratio e serialização da config de composição. |
| Modelo Dart | `lib/src/models/timeline_export_progress.dart` | Define estados de exportação e parsing dos eventos de progresso. |
| Modelo Dart | `lib/src/models/timeline_player_state.dart` | Define o estado emitido pelo player e converte mapas nativos em `Duration`/campos Dart. |
| API Dart | `lib/src/native_timeline_player.dart` | Orquestra load/export/comandos, guarda `textureId`, valida uso antes do load e expõe `stateStream`. |
| Platform interface | `lib/video_ultra_player_platform_interface.dart` | Contrato abstrato de preview, exportação, comandos e stream entre API Dart e implementação de plataforma. |
| Channel Dart | `lib/video_ultra_player_method_channel.dart` | Implementa o contrato com `MethodChannel`, `EventChannel` e retorno de path em `exportTimeline`. |
| iOS plugin | `ios/Classes/VideoUltraPlayerPlugin.swift` | Registra channels, gerencia controllers por textura, recebe comandos, exporta MP4 e emite estados. |
| iOS composição | `ios/Classes/TimelineComposition.swift` | Monta `AVMutableComposition`, `AVVideoComposition`, segmentos, duração total, fallback de imagem e asset exportável. |
| iOS textura | `ios/Classes/TimelineTexture.swift` | Liga `AVPlayerItemVideoOutput` ao `FlutterTexture` e notifica frames disponíveis. |
| Android plugin | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | Registra channels, gerencia controllers por textura, exporters ativos e valida argumentos. |
| Android composição | `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | Monta `CompositionPlayer`, `Transformer`, `Composition`, `SurfaceTexture`, efeitos, estado, exportação e dispose. |
| Exemplo | `example/lib/main.dart` | Demonstra load, render via `Texture`, play/pause, scrub, pan, galeria, exportação MP4 e dispose. |
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
- **Comandos exigem player carregado** — `lib/src/native_timeline_player.dart`: `_requireTextureId` impede `play`, `pause`, `seekTo`, `setVolume`, `setClipAlignment` e `stateStream` antes do `load`.
- **Exportação não exige preview carregado** — `lib/src/native_timeline_player.dart`: `exportTimeline` trabalha só com a lista de `TimelineClip` recebida e não chama `_requireTextureId`.
- **Um export ativo por player** — `lib/src/native_timeline_player.dart`: `exportTimeline` lança `StateError` se outra exportação ainda está em andamento; `exportProgress` só pode ser obtido durante um export ativo.
- **Config de composição é global** — `lib/src/models/timeline_composition_config.dart`: `transitionDuration`, `aspectRatio` e `baseWidth` valem para a composição inteira e são enviados tanto em `load` quanto em `exportTimeline`.
- **Transições encurtam a duração total** — `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: cada overlap subtrai tempo da soma sequencial; o estado usa os segmentos com overlap para calcular `totalDuration`, `clipIndex` e `localPosition`.
- **Aspect ratio usa cover-crop** — iOS aplica scale-to-fill/crop no transform da composição; Android usa `Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP`.
- **Volume aceito só entre 0 e 1** — `lib/src/native_timeline_player.dart`: valida no Dart; iOS e Android também fazem clamp no nativo.
- **`TimelineClip.scale` precisa ser positivo** — `lib/src/models/timeline_clip.dart`: assert no construtor; nativos também aplicam mínimo defensivo (`0.01`).
- **Estado sempre trafega em milissegundos** — `lib/src/models/timeline_player_state.dart`, `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: nativo emite números e Dart converte para `Duration`.
- **O `textureId` é o identificador do controller nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`: controllers ficam em mapas por textura.
- **Imagens têm duração explícita** — `example/lib/main.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: imagens usam duração informada ou fallback de 2 segundos.
- **Vídeos com duração informada podem ser cortados** — `ios/Classes/TimelineComposition.swift`: para vídeo, `duration(for:asset:)` usa `CMTimeMinimum` entre duração pedida e duração do asset.
- **Pan/crop trabalha em coordenadas normalizadas** — `example/lib/main.dart`, `lib/src/models/timeline_clip.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: `x/y` são tratados no intervalo `[-1, 1]`.
- **iOS usa fallback para imagem** — `ios/Classes/TimelineComposition.swift`: imagem é convertida em MP4 temporário com `AVAssetWriter` antes de entrar na composição.
- **Example mantém pan/crop para exportação** — `example/lib/main.dart`: o arrasto no vídeo também atualiza `_clips[state.clipIndex]` para que `exportTimeline(_clips)` use o alinhamento mais recente.
- **Android reconstrói a composição para pan/crop** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: efeitos Media3 são imutáveis, então `setClipAlignment` chama `setComposition(buildTimelineComposition(clips), positionMs)`.
- **Exportação Android mantém exporter vivo até finalizar** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`: `activeExporters` retém `TimelineCompositionExporter` e cancela exporters no detach do engine.
- **Dispose remove recursos nativos** — `ios/Classes/VideoUltraPlayerPlugin.swift`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: unregister/release da textura, player e recursos temporários.

## Dependências Externas

- **Flutter plugin channels** — `MethodChannel`, `EventChannel` e `Texture`/`TextureRegistry` são usados para comunicação e render.
- **image_picker 1.2.2** — usado no app de exemplo para selecionar múltiplos vídeos da galeria com `pickMultiVideo()`.
- **iOS AVFoundation** — `AVMutableComposition`, `AVVideoComposition`, `AVPlayer`, `AVPlayerItemVideoOutput`, `AVAssetWriter` e `AVAssetExportSession`.
- **Android Media3 1.10.1** — `androidx.media3:media3-common`, `androidx.media3:media3-effect`, `androidx.media3:media3-transformer`, `CompositionPlayer` e `Transformer`.
- **Android platform media APIs** — `MediaMetadataRetriever`, `Surface`, `SurfaceTexture`.
- **CocoaPods no example iOS** — `example/ios/Podfile` integra Flutter, `integration_test` e o plugin local.

## Observações

- O projeto é um Flutter plugin, então o fluxo não passa por Cubit, Repository ou DataSource. A fronteira arquitetural principal é API Dart → platform interface → channels → código nativo.
- O documento `flow/project-structure.md` ainda descreve o estado antigo de skeleton; este flow reflete o código atual depois da implementação do Native Timeline Player.
- O Android usa múltiplas sequências Media3 com gaps para permitir overlap visual no compositor; `setClipAlignment` reconstrói a `Composition` para aplicar novos efeitos mantendo a posição atual. A transição de áudio no Android permanece dependente do mixador padrão do Media3; o fade visual usa alpha ramp custom.
- O iOS usa uma única `AVMutableComposition` para preview e cria outra composição equivalente para exportação; imagens entram como vídeos temporários gerados localmente.
- `exportTimeline` retorna um path local, mas não move o arquivo para galeria/fotos; o app consumidor decide onde salvar/compartilhar o MP4 final.
- O example contém textos hardcoded porque é um app de demonstração do plugin, não uma tela de produto com l10n configurado.

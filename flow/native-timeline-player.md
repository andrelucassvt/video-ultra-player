# Flow: Native Timeline Player

> **Resumo:** Carrega uma timeline de clipes de vídeo/imagem, cria uma composição nativa única por plataforma, renderiza tudo em uma única `Texture` Flutter e expõe controles de playback, scrub, volume, pan/crop e estado.

## Visão Geral

O fluxo começa no app de exemplo em `example/lib/main.dart`. A tela tem dois caminhos de entrada: carregar os assets empacotados do demo ou abrir a galeria com `image_picker` para escolher vídeos do dispositivo. Em ambos os casos, a tela monta uma lista de `TimelineClip` com caminhos absolutos, tipo de mídia, duração/escala quando aplicável, e chama `NativeTimelinePlayer.load`.

No Dart do plugin, `NativeTimelinePlayer` valida que há ao menos um clipe, serializa cada `TimelineClip` com `toJson()` e delega para `VideoUltraPlayerPlatform.instance`. A implementação padrão é `MethodChannelVideoUltraPlayer`, que envia comandos pelo `MethodChannel('video_ultra_player/timeline_player')` e recebe estados pelo `EventChannel('video_ultra_player/timeline_player/events')`.

No iOS, `VideoUltraPlayerPlugin` recebe `load`, valida argumentos, cria um `TimelinePlayerController`, monta a timeline com `AVMutableComposition` em `TimelineComposition`, registra uma `TimelineTexture` no `FlutterTextureRegistry` e devolve o `textureId`. A textura usa `AVPlayerItemVideoOutput` com `CADisplayLink` para avisar o Flutter quando há novo frame.

No Android, `VideoUltraPlayerPlugin` recebe os mesmos comandos, cria um `TimelineCompositionController`, monta uma `Composition` com `CompositionPlayer`, registra um `SurfaceTexture` do Flutter, entrega esse `Surface` ao player e devolve o `textureId`. O estado é emitido periodicamente a cada ~33 ms pelo `EventChannel`.

O resultado final no Flutter é renderizado com `Texture(textureId: player.textureId)`. A UI do exemplo usa o `stateStream` para atualizar posição, clipe atual e estado de reprodução, e envia `play`, `pause`, `seekTo`, `setVolume`, `setClipAlignment` e `dispose` de volta pela mesma API pública.

## Passo a Passo

1. **App de exemplo** — `example/lib/main.dart` → `_TimelineDemoAppState.initState`
   Quando `autoLoad` é verdadeiro, chama `_loadTimeline()` ao iniciar a tela.

2. **App de exemplo / assets** — `example/lib/main.dart` → `_loadSampleTimeline` / `_copyAssetToTempFile`
   Copia `assets/clip_a.mp4`, `assets/still.png` e `assets/clip_b.mp4` para `Directory.systemTemp`, porque a camada nativa trabalha com paths de arquivo locais.

3. **App de exemplo / galeria** — `example/lib/main.dart` → `_pickVideosFromGallery`
   Abre o seletor de vídeos com `ImagePicker.pickMultiVideo()`. Se o usuário escolher vídeos, converte cada `XFile.path` em `TimelineClip(type: MediaType.video)`.

4. **App de exemplo** — `example/lib/main.dart` → `_replaceTimeline`
   Descarta a timeline anterior com `_player.dispose()`, carrega a nova lista de clipes com `_player.load(clips)`, atualiza `textureId`, `stateStream`, quantidade de clipes e origem da timeline.

5. **API Dart** — `lib/src/models/timeline_clip.dart` → `TimelineClip.toJson`
   Serializa cada clipe como `path`, `type`, `durationMs`, `alignment.x/y` e `scale`.

6. **API Dart** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.load`
   Rejeita timeline vazia com `ArgumentError`, chama `_platform.load(...)`, armazena o `textureId` e reseta o cache de `stateStream`.

7. **Platform Interface** — `lib/video_ultra_player_platform_interface.dart` → `VideoUltraPlayerPlatform.instance`
   Mantém o contrato abstrato da API nativa e usa `MethodChannelVideoUltraPlayer` como implementação padrão.

8. **Method Channel Dart** — `lib/video_ultra_player_method_channel.dart` → `MethodChannelVideoUltraPlayer.load`
   Envia `load` pelo channel `video_ultra_player/timeline_player` com `{'clips': clips}` e espera um `int` como `textureId`.

9. **iOS nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `register(with:)`
   Registra o `FlutterMethodChannel`, o `FlutterEventChannel` e mantém acesso ao `FlutterTextureRegistry`.

10. **iOS nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `load`
   Valida `clips`, converte os mapas em `TimelineClipDescriptor`, cria `TimelinePlayerController`, armazena o controller por `textureId` e retorna esse id ao Dart.

11. **iOS composição** — `ios/Classes/TimelineComposition.swift` → `TimelineComposition.build`
    Cria um `AVMutableComposition`, adiciona tracks de vídeo/áudio, insere cada clipe em sequência contínua e cria a tabela de `TimelineSegment` usada para calcular estado.

12. **iOS composição** — `ios/Classes/TimelineComposition.swift` → `makeVideoComposition`
    Gera `AVMutableVideoCompositionInstruction` por segmento e aplica transformações de orientação, escala cover e alinhamento via `AVMutableVideoCompositionLayerInstruction`.

13. **iOS textura** — `ios/Classes/TimelineTexture.swift` → `TimelineTexture`
    Conecta `AVPlayerItemVideoOutput` ao `AVPlayerItem`, registra frames com `CADisplayLink` e fornece `CVPixelBuffer` por `copyPixelBuffer()`.

14. **Android nativo** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `onAttachedToEngine`
    Registra `MethodChannel`, `EventChannel`, `applicationContext` e `TextureRegistry`.

15. **Android nativo** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `load`
    Valida a lista `clips`, cria `TimelineCompositionController`, chama `controller.load(clips)`, armazena o controller por `textureId` e retorna esse id ao Dart.

16. **Android composição** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `load`
    Converte os mapas em `TimelineClip`, resolve durações, cria um `SurfaceTexture` Flutter, cria um `Surface`, instancia `CompositionPlayer`, configura a superfície de vídeo e prepara a composição.

17. **Android composição** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `buildComposition`
    Cria `MediaItem`/`EditedMediaItem` para cada clipe, usa `setImageDurationMs` para imagens, força `durationUs` em todos os itens, monta uma `EditedMediaItemSequence` e devolve uma `Composition`.

18. **Render Flutter** — `example/lib/main.dart` → `Texture`
    Quando `_textureId` existe, renderiza `Texture(textureId: _textureId!)` dentro de um `AspectRatio`.

19. **Estado Dart** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.stateStream`
    Exige que `load` já tenha completado, pede `_platform.stateStream(textureId)` e converte o stream para broadcast.

20. **Estado nativo iOS** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController.emitState`
    Usa `AVPlayer.currentTime()`, cruza a posição com `TimelineComposition.playbackState`, e emite `globalPosition`, `clipIndex`, `localPosition`, `isPlaying` e `totalDuration`.

21. **Estado nativo Android** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `emitState`
    Usa `CompositionPlayer.currentPosition`, calcula o índice do segmento atual e emite o mesmo mapa de estado pelo `EventChannel`.

22. **Controles Dart** — `example/lib/main.dart` → botões, slider e pan
    Botão alterna `play/pause`; slider chama `seekTo(Duration)` no fim do arrasto; pan no `Texture` converte posição local para `x/y` em `[-1, 1]` e chama `setClipAlignment`.

23. **Commands Dart** — `lib/src/native_timeline_player.dart` → `play`, `pause`, `seekTo`, `setVolume`, `setClipAlignment`, `dispose`
    Todos exigem `textureId` carregado; `setVolume` valida faixa `0.0..1.0`; `dispose` limpa `textureId`, stream local e chama a plataforma.

24. **Commands nativos** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`
    Cada comando busca o controller pelo `textureId` e delega para o controller nativo correspondente.

25. **Limpeza** — `ios/Classes/VideoUltraPlayerPlugin.swift` / `TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`
    `dispose` pausa/release o player, remove observer/timer, unregister/release da textura e limpa recursos temporários.

### Caminhos alternativos

- **Timeline vazia no Dart:** `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.load` lança `ArgumentError` antes de chamar a plataforma.
- **Comando antes do load:** `lib/src/native_timeline_player.dart` → `_requireTextureId` lança `StateError`.
- **Volume fora de faixa:** `lib/src/native_timeline_player.dart` → `setVolume` lança `RangeError`.
- **Seleção cancelada na galeria:** `example/lib/main.dart` → `_pickVideosFromGallery` mantém a timeline atual e apenas encerra o estado de loading.
- **Erro do picker:** `example/lib/main.dart` → `_pickVideosFromGallery` captura `PlatformException` e exibe a mensagem em `_error`.
- **Argumentos inválidos no iOS:** `ios/Classes/VideoUltraPlayerPlugin.swift` → `load`, `textureId(from:result:)` e `onListen` retornam `FlutterError` com `invalid_arguments` ou `invalid_clip`.
- **Argumentos inválidos no Android:** `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `load`, `withController`, `seekTo`, `setVolume` e `setClipAlignment` retornam `result.error(...)`.
- **Controller não encontrado:** `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` retornam erro `not_found` quando o `textureId` não existe mais.
- **Falha de composição:** iOS retorna `FlutterError(code: "load_failed")` em `ios/Classes/VideoUltraPlayerPlugin.swift`; Android retorna `result.error("load_failed", ...)` em `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`.
- **Erro de playback Android:** `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` → `Player.Listener.onPlayerError` propaga `playback_error` pelo `EventChannel`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública Dart | `lib/video_ultra_player.dart` | Exporta `NativeTimelinePlayer`, `TimelineClip`, `MediaType` e `TimelinePlayerState`. |
| Modelo Dart | `lib/src/models/timeline_clip.dart` | Define clipes de timeline e serialização para o contrato nativo. |
| Modelo Dart | `lib/src/models/timeline_player_state.dart` | Define o estado emitido pelo player e converte mapas nativos em `Duration`/campos Dart. |
| API Dart | `lib/src/native_timeline_player.dart` | Orquestra load/comandos, guarda `textureId`, valida uso antes do load e expõe `stateStream`. |
| Platform interface | `lib/video_ultra_player_platform_interface.dart` | Contrato abstrato de comandos e stream entre API Dart e implementação de plataforma. |
| Channel Dart | `lib/video_ultra_player_method_channel.dart` | Implementa o contrato com `MethodChannel` e `EventChannel`. |
| iOS plugin | `ios/Classes/VideoUltraPlayerPlugin.swift` | Registra channels, gerencia controllers por textura, recebe comandos e emite estados. |
| iOS composição | `ios/Classes/TimelineComposition.swift` | Monta `AVMutableComposition`, `AVVideoComposition`, segmentos, duração total e fallback de imagem. |
| iOS textura | `ios/Classes/TimelineTexture.swift` | Liga `AVPlayerItemVideoOutput` ao `FlutterTexture` e notifica frames disponíveis. |
| Android plugin | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | Registra channels, gerencia controllers por textura e valida argumentos. |
| Android composição | `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | Monta `CompositionPlayer`, `Composition`, `SurfaceTexture`, efeitos, estado e dispose. |
| Exemplo | `example/lib/main.dart` | Demonstra load, render via `Texture`, play/pause, scrub, pan e dispose. |
| Assets do exemplo | `example/assets/clip_a.mp4` | Primeiro clipe de vídeo do demo. |
| Assets do exemplo | `example/assets/still.png` | Clipe de imagem do demo. |
| Assets do exemplo | `example/assets/clip_b.mp4` | Segundo clipe de vídeo do demo. |
| Configuração package | `pubspec.yaml` | Declara o plugin Flutter e as plataformas Android/iOS. |
| Configuração example | `example/pubspec.yaml` | Declara dependência local no plugin e assets usados pelo demo. |
| Configuração iOS example | `example/ios/Runner/Info.plist` | Declara `NSPhotoLibraryUsageDescription` para permitir seleção de vídeos da biblioteca no iOS. |
| Configuração Android | `android/build.gradle.kts` | Declara dependências Media3 `common`, `effect` e `transformer` na versão `1.10.1`. |
| Configuração iOS example | `example/ios/Podfile` | Configura CocoaPods para o app de exemplo Flutter/iOS. |
| Testes Dart | `test/native_timeline_player_test.dart` | Cobre API pública, serialização, validações, commands, textureId e stream. |
| Testes Dart | `test/video_ultra_player_method_channel_test.dart` | Cobre payloads enviados pelo `MethodChannel` e conversão de estado. |
| Testes Android | `android/src/test/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPluginTest.kt` | Cobre fallback `notImplemented` para método desconhecido. |
| Testes example | `example/test/widget_test.dart` | Cobre renderização inicial dos controles do demo. |
| Testes example | `example/integration_test/plugin_integration_test.dart` | Cobre conversão básica de `TimelinePlayerState.fromMap`. |
| Testes iOS example | `example/ios/RunnerTests/RunnerTests.swift` | Cobre fallback `FlutterMethodNotImplemented` para método desconhecido. |

## Regras de Negócio Relevantes

- **A timeline precisa ter pelo menos um clipe** — `lib/src/native_timeline_player.dart`: `load` lança `ArgumentError` se a lista estiver vazia; Android também usa `require(rawClips.isNotEmpty())`.
- **Comandos exigem player carregado** — `lib/src/native_timeline_player.dart`: `_requireTextureId` impede `play`, `pause`, `seekTo`, `setVolume`, `setClipAlignment` e `stateStream` antes do `load`.
- **Volume aceito só entre 0 e 1** — `lib/src/native_timeline_player.dart`: valida no Dart; iOS e Android também fazem clamp no nativo.
- **`TimelineClip.scale` precisa ser positivo** — `lib/src/models/timeline_clip.dart`: assert no construtor; nativos também aplicam mínimo defensivo (`0.01`).
- **Estado sempre trafega em milissegundos** — `lib/src/models/timeline_player_state.dart`, `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: nativo emite números e Dart converte para `Duration`.
- **O `textureId` é o identificador do controller nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`: controllers ficam em mapas por textura.
- **Imagens têm duração explícita** — `example/lib/main.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: imagens usam duração informada ou fallback de 2 segundos.
- **Vídeos com duração informada podem ser cortados** — `ios/Classes/TimelineComposition.swift`: para vídeo, `duration(for:asset:)` usa `CMTimeMinimum` entre duração pedida e duração do asset.
- **Pan/crop trabalha em coordenadas normalizadas** — `example/lib/main.dart`, `lib/src/models/timeline_clip.dart`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: `x/y` são tratados no intervalo `[-1, 1]`.
- **iOS usa fallback para imagem** — `ios/Classes/TimelineComposition.swift`: imagem é convertida em MP4 temporário com `AVAssetWriter` antes de entrar na composição.
- **Android reconstrói a composição para pan/crop** — `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: efeitos Media3 são imutáveis, então `setClipAlignment` chama `setComposition(buildComposition(), positionMs)`.
- **Dispose remove recursos nativos** — `ios/Classes/VideoUltraPlayerPlugin.swift`, `ios/Classes/TimelineComposition.swift` e `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt`: unregister/release da textura, player e recursos temporários.

## Dependências Externas

- **Flutter plugin channels** — `MethodChannel`, `EventChannel` e `Texture`/`TextureRegistry` são usados para comunicação e render.
- **image_picker 1.2.2** — usado no app de exemplo para selecionar múltiplos vídeos da galeria com `pickMultiVideo()`.
- **iOS AVFoundation** — `AVMutableComposition`, `AVVideoComposition`, `AVPlayer`, `AVPlayerItemVideoOutput` e `AVAssetWriter`.
- **Android Media3 1.10.1** — `androidx.media3:media3-common`, `androidx.media3:media3-effect`, `androidx.media3:media3-transformer`.
- **Android platform media APIs** — `MediaMetadataRetriever`, `Surface`, `SurfaceTexture`.
- **CocoaPods no example iOS** — `example/ios/Podfile` integra Flutter, `integration_test` e o plugin local.

## Observações

- O projeto é um Flutter plugin, então o fluxo não passa por Cubit, Repository ou DataSource. A fronteira arquitetural principal é API Dart → platform interface → channels → código nativo.
- O documento `flow/project-structure.md` ainda descreve o estado antigo de skeleton; este flow reflete o código atual depois da implementação do Native Timeline Player.
- O Android usa uma única sequência Media3 (`EditedMediaItemSequence.withAudioAndVideoFrom`) e uma única textura Flutter, mas `setClipAlignment` reconstrói a `Composition` para aplicar novos efeitos mantendo a posição atual.
- O iOS usa uma única `AVMutableComposition` e uma única textura Flutter; imagens entram como vídeos temporários gerados localmente.
- O example contém textos hardcoded porque é um app de demonstração do plugin, não uma tela de produto com l10n configurado.

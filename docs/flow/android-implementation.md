---
generated_at: 2026-07-31
source_commit: 00e2335
source_state: clean
verified_at: 2026-08-02
status: current
related_plans:
  - docs/plan/onda-1-quick-wins.md
  - docs/plan/onda-2-identidade-editor.md
  - docs/plan/text-overlays/00-indice.md
---

# Flow: Camada Nativa Android

> **Resumo:** Implementação Kotlin que recebe os comandos do MethodChannel, monta uma `Composition` Media3 tocada por `CompositionPlayer` sobre um `SurfaceTexture` do Flutter, e exporta a mesma composição com `Transformer`.

## Visão Geral

A camada Android vive em `android/src/main/kotlin/com/andre/video_ultra_player/` e tem quatro arquivos. `VideoUltraPlayerPlugin` é o `FlutterPlugin`: em `onAttachedToEngine` guarda `applicationContext` e `textureRegistry`, abre o `MethodChannel` de comandos e os dois `EventChannel` (estado e progresso de export), e mantém `controllers: MutableMap<Long, TimelineCompositionController>` mais `activeExporters`. Cada method call de player passa por `withController(call, result)`, que extrai o `textureId` e resolve o controller — erro `invalid_arguments` sem id, `not_found` sem controller.

`TimelineCompositionController.load` faz o caminho completo: parseia os clipes (`parseTimelineClips` → `TimelineClip.from` → `resolveClip`, que consulta `MediaMetadataRetriever`/`BitmapFactory` para descobrir duração e dimensões da fonte), calcula o `renderSize` de saída, monta os segmentos, cria o `SurfaceTextureEntry` com `setDefaultBufferSize(renderSize)`, envolve o `SurfaceTexture` num `Surface`, constrói o `CompositionPlayer`, entrega o surface com `setVideoSurface`, registra um `Player.Listener` que empurra erros de playback pelo `EventChannel` de estado, chama `setComposition` + `prepare` e agenda o `stateRunnable` de 33 ms. O `entry.id()` é o `textureId` devolvido ao Dart.

A composição é montada por `buildTimelineComposition`: cada clipe vira um `EditedMediaItem` (`editedMediaItemFor`) com `ClippingConfiguration` para trim, `setImageDurationMs`/`setFrameRate(30)` para imagem, `setDurationUs` com a duração **da fonte** (Media3 valida `clippingEnd * 1000 <= durationUs`), efeitos de `Crop` + `Presentation` (`LAYOUT_SCALE_TO_FIT_WITH_CROP`) e um `SpeedProvider` constante quando `speed != 1.0`. Todos entram numa `EditedMediaItemSequence.withAudioAndVideoFrom(items)`. Se existe trilha externa e seu offset cabe na timeline, `audioSequenceFor` adiciona uma segunda sequência só de áudio, com gap inicial para o offset, clipping para o trim e um `GainProcessor` com `AudioTrackGainProvider` fazendo volume + fade in/out por posição de sample.

Text overlays entram como efeito por clipe: `buildTimelineComposition` acumula o `clipStartMs` de cada segmento, filtra/re-ancora os overlays da timeline para a janela do clipe com `textOverlaysForClip` (função pura) e `effectsFor` adiciona um `OverlayEffect` de `TimelineTextOverlay` **depois** do `Presentation` — efeitos Media3 são imutáveis, então toda mutação de texto passa por `rebuildCompositionPreservingPlayback()` (commit-only).

Toda edição segue o mesmo padrão: `pushEditSnapshot()` → mutar a lista `clips` (ou `audioTrack`) → `rebuildCompositionPreservingPlayback()`, que recalcula os segmentos, lê a posição atual, chama `setComposition(novaComposition, positionMs)` + `prepare()` e retoma o play se estava tocando. Efeitos Media3 são imutáveis, então até `setClipAlignment` passa por rebuild completo — diferente do iOS, onde alinhamento é inline.

Export tem duas portas: `exportTimeline` (a partir de uma lista de clipes crua, sem player) cria um `TimelineCompositionExporter` direto no plugin; `exportCurrentTimeline` pede ao controller (`startExportCurrentTimeline`) um exporter alimentado com a lista de clipes, o `renderSize` e a trilha de áudio **atuais**, garantindo que o MP4 corresponda ao preview. O exporter roda `Transformer.start` e poleia `getProgress(ProgressHolder)` a cada 100 ms.

`ThumbnailGenerator` é independente do player: roda no `thumbnailExecutor` do plugin, extrai frames com `MediaMetadataRetriever` e cacheia JPEGs em `context.cacheDir/vup_thumbs/`.

## Passo a Passo

1. **Attach** — `.../VideoUltraPlayerPlugin.kt` → `onAttachedToEngine`
   Guarda contexto e `textureRegistry`; abre `video_ultra_player/timeline_player`, `.../events` e `.../export`.
2. **Roteamento** — `onMethodCall`
    `when (call.method)` sobre `load`, `exportTimeline`, `play`, `pause`, `seekTo`, `seekToClip`, `setVolume`, `setClipAlignment`, `trimClip`, `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip`, `setClipSpeed`, `setAudioTrack`, `removeAudioTrack`, `addTextOverlay`, `updateTextOverlay`, `removeTextOverlay`, `undo`, `redo`, `generateThumbnails`, `exportCurrentTimeline`, `dispose`; o resto vira `result.notImplemented()`.
3. **Resolução do controller** — `withController(call, result, block)`
   `numberArg(arguments, "textureId")` → `controllers[textureId]`.
4. **Load** — `.../TimelineCompositionController.kt` → `load(rawClips, rawConfig)`
   `TimelineCompositionConfig.from` → `parseTimelineClips` → `outputSizeFor` → `rebuildSegments`.
5. **Resolução de metadados** — `resolveClip` → `resolveSourceDurationMs` / `resolveSourceSize`
   `MediaMetadataRetriever` para vídeo (inclusive rotação 90/270, que troca largura e altura) e `BitmapFactory` com `inJustDecodeBounds` para imagem.
6. **Textura e player** — `textureRegistry.createSurfaceTexture()` → `Surface(entry.surfaceTexture())` → `CompositionPlayer.Builder(context).build()`
   `setVideoSurface(surface, Size(renderSize))`, `addListener { onPlayerError }`, `setComposition(...)`, `prepare()`.
7. **Composição** — `buildTimelineComposition(clips, renderSize, audioTrack, textOverlays)`
    `editedMediaItemFor` por clipe + `EditedMediaItemSequence.withAudioAndVideoFrom`; adiciona `audioSequenceFor` quando há trilha externa dentro da duração da timeline. Para cada clipe, `textOverlaysForClip` filtra os overlays que intersectam a janela do clipe e re-ancora `startMs`/`endMs` (timestamps do Media3 são relativos ao item).
8. **Efeitos por clipe** — `effectsFor(clip, renderSize, clipOverlays)`
    `Crop` derivado de `scale`/`alignment` quando `scale > 1.0001`, seguido de `Presentation.createForWidthAndHeight(..., LAYOUT_SCALE_TO_FIT_WITH_CROP)` e, se o clipe tem overlays, um `OverlayEffect` de `TimelineTextOverlay` depois do `Presentation` — o texto não passa pelo crop/scale do clipe.
9. **Estado** — `stateRunnable` → `emitState()` a cada `STATE_INTERVAL_MS` (33 ms)
   Emite `globalPosition`, `clipIndex` (`segmentIndexFor`), `localPosition`, `isPlaying`, `totalDuration`, `clipDurationsMs`, `canUndo`, `canRedo`.
10. **Playback** — `play` / `pause` / `seekTo` / `seekToClip` / `setVolume`
    `seekTo` faz `coerceIn(0, totalDurationMs)`; `seekToClip` usa `segments.getOrNull(clipIndex)?.startMs`; `setVolume` faz `coerceIn(0.0, 1.0)`.
11. **Edição** — `trimClip` / `splitClip` / `insertClip` / `removeClip` / `moveClip` / `replaceClip` / `setClipSpeed` / `setClipAlignment`
    Cada um valida o índice, chama `pushEditSnapshot()`, muta `clips` e chama `rebuildCompositionPreservingPlayback()`.
12. **Trilha de áudio** — `setAudioTrack(rawTrack)` / `removeAudioTrack()`
    `AudioTrackDescriptor.from` + `resolveAudioTrack` (resolve `sourceDurationMs`) e rebuild; remover sem trilha ativa só re-emite estado.
13. **Text overlays** — `addTextOverlay(rawOverlay)` / `updateTextOverlay(rawOverlay)` / `removeTextOverlay(overlayId)`
    `pushEditSnapshot()` → mutar `textOverlays` (update/remove são no-op com `emitState()` quando o `id` não existe) → `rebuildCompositionPreservingPlayback()`. `TextOverlayDescriptor.from` lança quando `id`/`text` faltam e faz clamp de `x`/`y`/`fontSize`/`opacity`.
14. **Undo/redo** — `undo()` / `redo()` → `TimelineEditModel` → `restoreEditSnapshot`
    Restaura `clips` + `audioTrack` + `textOverlays` do snapshot e faz rebuild; pilha vazia é no-op com `emitState()`.
15. **Export da timeline crua** — `VideoUltraPlayerPlugin.exportTimeline` → `TimelineCompositionExporter.export`
    Parseia clipes/config, calcula `outputSizeFor` e delega a `exportFromClips` sem trilha de áudio e sem overlays (`emptyList()`).
16. **Export do estado atual** — `exportCurrentTimeline` → `TimelineCompositionController.startExportCurrentTimeline` → `exportFromClips`
    Passa `clips`, `renderSize`, `audioTrack` e `textOverlays` correntes — o MP4 sai com os textos do preview.
17. **Transformer** — `TimelineCompositionExporter.exportFromClips`
    Cria diretório/apaga arquivo existente, `Transformer.Builder(context).addListener{...}.build()`, `start(composition, path)` e agenda `progressRunnable` (100 ms).
18. **Thumbnails** — `VideoUltraPlayerPlugin.generateThumbnails` → `ThumbnailGenerator.generate`
    Roda no `thumbnailExecutor`; devolve o resultado via `mainHandler.post { result.success(paths) }`.
19. **Dispose** — `dispose` no plugin → `TimelineCompositionController.dispose`
    Marca `disposed`, remove o `stateRunnable`, libera player, `Surface` e `SurfaceTextureEntry`.
20. **Detach** — `onDetachedFromEngine`
    Limpa os handlers dos canais, cancela `activeExporters`, dispõe todos os controllers e encerra o `thumbnailExecutor`.

### Caminhos alternativos

- **Plugin sem contexto/registry:** `load`, `exportTimeline` e `generateThumbnails` respondem `not_attached`.
- **Argumento numérico ausente:** `result.error("invalid_arguments", …)` com a mensagem do campo esperado.
- **Controller inexistente:** `not_found` (`No native timeline player exists for textureId …`).
- **Falha em `insertClip`/`replaceClip`/`setAudioTrack`:** `try/catch` no plugin converte em `edit_failed`; `setAudioTrack` também loga com `Log.e` e devolve o stack trace em `details`.
- **Falha ao montar a composição no load:** `load_failed`.
- **Índice fora de faixa:** os métodos do controller retornam sem alterar nada (`if (clipIndex !in clips.indices) return`).
- **Erro de playback:** `Player.Listener.onPlayerError` monta uma mensagem com até 5 níveis de `cause` e chama `eventSink?.error("playback_error", msg, null)`.
- **Falha de export:** `Transformer.Listener.onError` apaga o arquivo de saída, emite `state: "failed"` e devolve `export_failed`; exceções na montagem também caem em `export_failed` com `exporter.cancel()`.
- **Trilha de áudio fora da timeline:** `buildTimelineComposition` ignora a sequência de áudio quando `audioTrack.offsetMs >= timelineDurationMs`.
- **Extração de thumbnail falha:** `generateFrame` devolve `null` e o timestamp é omitido do resultado (`mapNotNull`).

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Plugin / dispatcher | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | Canais, mapa de controllers, exporters ativos, parsing de argumentos, thumbnails |
| Controller | `.../TimelineCompositionController.kt` → `TimelineCompositionController` | `CompositionPlayer`, `Surface`, segmentos, edição, estado, dispose |
| Builders / modelos | `.../TimelineCompositionController.kt` (top-level) | `buildTimelineComposition`, `editedMediaItemFor`, `audioSequenceFor`, `effectsFor`, `TimelineClip`, `AudioTrackDescriptor`, `TimelineCompositionConfig`, `AudioTrackGainProvider` |
| Textos | `.../TextOverlay.kt` | `TextOverlayDescriptor`, função pura `textOverlaysForClip`, `TimelineTextOverlay : TextOverlay` (spans + `StaticOverlaySettings`) |
| Exporter | `.../TimelineCompositionController.kt` → `TimelineCompositionExporter` | `Transformer`, polling de progresso, arquivo de saída |
| Histórico | `.../TimelineEditModel.kt` | `TimelineEditSnapshot` (clips + áudio + textos) e pilhas undo/redo (limite 50) |
| Thumbnails | `.../ThumbnailGenerator.kt` | `MediaMetadataRetriever` + cache em `cacheDir/vup_thumbs` |
| Build | `android/build.gradle.kts` | Media3 1.10.1, JVM 17, `compileSdk 36`, `minSdk 24`, JUnit Platform |
| Testes | `android/src/test/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPluginTest.kt` | Método desconhecido → `notImplemented()` |
| Testes | `android/src/test/kotlin/com/andre/video_ultra_player/TextOverlayDescriptorTest.kt` | Parsing do descriptor, clamps, `textOverlaysForClip`, round-trip do snapshot |
| Contraparte Dart | `lib/video_ultra_player_method_channel.dart` | Nomes de método e chaves esperadas por este código |

## Regras de Negócio Relevantes

- **`setDurationUs` usa a duração da fonte, não a cortada** — `editedMediaItemFor`: Media3 valida `clippingEndPositionMs * 1000 <= durationUs`; usar a duração cortada quebra o invariante sempre que `trimStartMs > 0` (por exemplo depois de um split). O comentário no código registra isso.
- **Todo rebuild preserva posição e estado de play** — `rebuildCompositionPreservingPlayback`: `setComposition(composition, positionMs.coerceIn(0, totalDurationMs))` e `play()` se `wasPlaying`.
- **Alinhamento exige rebuild** — efeitos Media3 são imutáveis; `setClipAlignment` reconstrói a composição inteira (documentado também em `setClipSpeed`/`setAudioTrack`: chamar só no commit do controle, não a cada tick de arrasto).
- **`scale` só recorta acima de 1** — `effectsFor` usa `max(clip.scale, 1.0)` e só adiciona `Crop` quando `scale > 1.0001`.
- **`resolvedDurationMs` prioriza `trimEndMs`** — depois cai em `sourceDurationMs` e por fim em `durationMs`/2000 ms; `scaledDurationMs` divide por `speed`.
- **Áudio externo é clampado pela timeline** — `audioSequenceFor`: `effectiveDurationMs = min(trimmedDurationMs, timelineDurationMs - offsetMs)` para que `durationUs` case com o range de clipping exigido pelo Media3.
- **Fades são calculados por posição de sample** — `AudioTrackGainProvider.getGainFactorAtSamplePosition` converte sample → µs e multiplica o ganho pelas rampas de fade-in/fade-out.
- **`speed` clampado em `[0.5, 2.0]`** — em `TimelineClip.from`, em `setClipSpeed` e em `constantSpeedProvider`.
- **`volume` clampado em `[0.0, 1.0]`** — em `AudioTrackDescriptor.from` e em `setVolume`.
- **Dimensões sempre pares** — `evenDimension` em `outputSizeFor` e `resolveSourceSize`.
- **Histórico limitado a 50 snapshots** — `TimelineEditModel`; `pushSnapshot` limpa a pilha de redo.
- **Rotação da fonte é respeitada** — `resolveSourceSize` inverte largura/altura quando `METADATA_KEY_VIDEO_ROTATION` é 90 ou 270.
- **Export do estado atual inclui a trilha externa** — `startExportCurrentTimeline` captura `clips`, `renderSize` e `audioTrack` correntes antes de criar o exporter.
- **Overlays são re-ancorados por clipe** — `textOverlaysForClip`: timestamps de efeito no Media3 são relativos ao `EditedMediaItem`; a função intersecta `[clipStartMs, clipStartMs + clipDurationMs)` e subtrai `clipStartMs` da janela (clamps em 0 e na duração do clipe). Overlay que não intersecta nenhum clipe não vira efeito.
- **`OverlayEffect` entra depois do `Presentation`** — `effectsFor` adiciona os textos ao final da lista de efeitos de vídeo, para não serem cortados/escalados pelo crop do clipe.
- **`TimelineTextOverlay` renderiza string vazia fora da janela** — `getText` devolve `SpannableString("")` fora de `[startMs, endMs)` (tempo convertido de µs para ms), no-op de render.
- **Fonte custom cacheada** — `TimelineTextOverlay.typefaceFor` cacheia `Typeface` por path num `companion object` (evita I/O de `Typeface.createFromFile` por frame) e cai em `Typeface.DEFAULT`.
- **Mutações de texto são commit-only** — `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` reconstróem a `Composition` (efeitos imutáveis); o app exemplo chama apenas no commit do gesto.

## Dependências Externas

- **`androidx.media3` 1.10.1:** `CompositionPlayer`, `Composition`, `EditedMediaItem`, `EditedMediaItemSequence`, `Transformer`, `ProgressHolder`, `Effects`, `Crop`, `Presentation`, `GainProcessor`, `SpeedProvider`, `TextOverlay`, `OverlayEffect`, `StaticOverlaySettings`.
- **Android framework:** `MediaMetadataRetriever`, `BitmapFactory`, `Surface`, `SurfaceTexture`, `Handler`/`Looper`, `Executors`.
- **Flutter Android embedder:** `FlutterPlugin`, `MethodChannel`, `EventChannel`, `io.flutter.view.TextureRegistry`.

## Observações

- `resolveClip` faz I/O de metadados de forma síncrona: em `load`, `insertClip` e `replaceClip` isso roda na thread do channel (main), ao contrário das thumbnails, que usam `thumbnailExecutor`.
- `transitionToNextMs` é parseado e preservado em `TimelineClip`, mas nenhuma parte da composição o usa — não há crossfade; o split apenas o zera.
- `TimelineCompositionExporter.cancel()` marca `completed = true`, então um exporter cancelado nunca reporta resultado — é o comportamento esperado no `onDetachedFromEngine`.
- `exportTimeline` (lista crua) sempre exporta sem trilha de áudio externa e sem text overlays: `export` chama `exportFromClips(..., emptyList(), ...)` — paridade com a trilha de áudio.
- `emitState` roda a cada 33 ms enquanto o controller existir, mesmo pausado — é o que mantém `canUndo`/`canRedo` atualizados sem evento dedicado.
- A cobertura automatizada é `VideoUltraPlayerPluginTest` (método desconhecido) e `TextOverlayDescriptorTest` (parsing, janela por clipe e snapshot); nada exercita composição, edição ou export end-to-end.
- `VideoUltraPlayerPlugin.mainHandler` é `lazy`: permite construir o plugin em teste JVM puro sem `Looper` mockado (falha pré-existente corrigida junto da feature de textos).

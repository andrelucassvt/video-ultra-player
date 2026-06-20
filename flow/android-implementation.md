# Flow: Implementação Android — Plugin VideoUltraPlayer

> **Resumo:** Detalha como os quatro arquivos Kotlin do plugin recebem comandos do Flutter, constroem e controlam uma `Composition` Media3, emitem estado periódico, gerenciam histórico de edições e produzem thumbnails e exportações de vídeo.

## Visão Geral

A implementação Android vive em `android/src/main/kotlin/com/andre/video_ultra_player/` e é composta por quatro arquivos. `VideoUltraPlayerPlugin` é o ponto de entrada do `FlutterPlugin` e age como dispatcher de comandos: abre três canais de comunicação com o Dart, gerencia um mapa de `textureId → TimelineCompositionController` e delega cada method call para o controller correto. `TimelineCompositionController` encapsula todo o estado de playback — um `CompositionPlayer` Media3, um `SurfaceTexture` do `TextureRegistry` do Flutter e o histórico de edição — além de conter as classes de dados (`TimelineClip`, `AudioTrackDescriptor`, `TimelineCompositionConfig`) e os builders que montam a `Composition` Media3. `TimelineCompositionExporter` encapsula o `Transformer` Media3 e poleia o progresso via `Handler`. `TimelineEditModel` é uma pilha dupla de desfazer/refazer com limite de 50 snapshots. `ThumbnailGenerator` extrai frames JPEG de vídeos com cache em disco.

Os canais Dart↔Android são:
- **MethodChannel** `video_ultra_player/timeline_player` — todos os comandos síncronos e assíncronos.
- **EventChannel** `video_ultra_player/timeline_player/events` — estado de playback a ~33 ms.
- **EventChannel** `video_ultra_player/timeline_player/export` — progresso de exportação a ~100 ms.

---

## Passo a Passo

### A. Inicialização do plugin

1. **Plugin registrado pelo Flutter engine** — `VideoUltraPlayerPlugin.kt` → `onAttachedToEngine`
   O engine chama `onAttachedToEngine` com o `FlutterPluginBinding`. O plugin salva `applicationContext` e `textureRegistry`, instancia os três canais e registra handlers (`setMethodCallHandler` / `setStreamHandler`). A instância `exportProgressHandler` (inner class `ExportProgressStreamHandler`) é criada uma vez e compartilhada entre todas as exportações.

### B. Load — construção da timeline

2. **Dart envia `load`** — `VideoUltraPlayerPlugin.kt:264` → `load(call, result)`
   O dispatcher identifica `call.method == "load"`, extrai `clips` (lista de mapas) e `config` (mapa opcional) dos argumentos e chama `load()`.

3. **Criação do controller** — `TimelineCompositionController.kt:69` → `TimelineCompositionController.load`
   - `TimelineCompositionConfig.from(rawConfig)` parseia aspect ratio e baseWidth.
   - `parseTimelineClips` converte cada mapa bruto em `TimelineClip` via `TimelineClip.from()`, depois chama `resolveClip` em cada um.

4. **Resolução de metadados nativos** — `TimelineCompositionController.kt:683` → `resolveClip`
   Para cada clipe, `resolveSourceSize` abre um `MediaMetadataRetriever` para ler largura, altura e rotação (trocando largura/altura se rotação == 90° ou 270°). Se o clipe for vídeo, `resolveSourceDurationMs` lê a duração real do arquivo. Esses valores populam `sourceDurationMs`, `sourceWidth` e `sourceHeight` no `TimelineClip`.

5. **Cálculo do tamanho de render** — `TimelineCompositionController.kt:770` → `outputSizeFor`
   Usa o `aspectRatio` da config para calcular `renderSize` a partir de `baseWidth` (padrão 1080 px). Garante dimensões pares com `evenDimension`.

6. **Criação da textura Flutter** — `TimelineCompositionController.kt:78`
   `textureRegistry.createSurfaceTexture()` aloca uma `SurfaceTextureEntry`; `setDefaultBufferSize(width, height)` define a resolução; um `Surface` é criado a partir do `surfaceTexture`.

7. **Construção da `Composition` Media3** — `TimelineCompositionController.kt:525` → `buildTimelineComposition`
   Para cada `TimelineClip`, `editedMediaItemFor` cria um `MediaItem` com URI local, `ClippingConfiguration` (se houver trim), `durationUs` (duração completa da fonte — necessária para validação interna do Media3), `effectsFor` (efeitos) e opcionalmente um `SpeedProvider` constante.

   - **`effectsFor`**: Se `scale > 1`, calcula coordenadas de `Crop` com base em `alignmentX/Y`. Em seguida adiciona sempre `Presentation.createForWidthAndHeight(..., LAYOUT_SCALE_TO_FIT_WITH_CROP)` para uniformizar o output size de todos os clipes.
   - **Trilha de áudio externa**: Se `audioTrack != null`, `audioSequenceFor` cria uma `EditedMediaItemSequence` apenas de áudio com clipping, fade in/out via `AudioTrackGainProvider` e gap inicial (`offsetMs`).

   O resultado é `Composition.Builder(sequences).build()` com 1 sequência de vídeo+áudio e 0 ou 1 sequência de áudio extra.

8. **Inicialização do `CompositionPlayer`** — `TimelineCompositionController.kt:85`
   `CompositionPlayer.Builder(context).build()` → `setVideoSurface(renderSurface, Size)` → `setComposition(composition)` → `prepare()`. Um listener captura `onPlayerError` e propaga via `eventSink`.

9. **Start do loop de estado** — `TimelineCompositionController.kt:117`
   `mainHandler.post(stateRunnable)` inicia o loop de 33 ms que chama `emitState()` enquanto `!disposed`.

10. **Retorno do `textureId`** — `VideoUltraPlayerPlugin.kt:291`
    O controller é inserido em `controllers[textureId]`. O plugin responde `result.success(textureId)` para o Dart.

---

### C. Comandos de playback

11. **`play` / `pause`** — `TimelineCompositionController.kt:126,131`
    Chama `player?.play()` ou `player?.pause()` e `emitState()` imediatamente.

12. **`seekTo`** — `TimelineCompositionController.kt:136`
    Clampeia `positionMs` em `[0, totalDurationMs]` antes de repassar ao player.

13. **`seekToClip`** — `TimelineCompositionController.kt:141`
    Localiza `segments[clipIndex].startMs` e delega para `seekTo`.

14. **`setVolume`** — `TimelineCompositionController.kt:147`
    Clampeia em `[0.0, 1.0]` e ajusta `player.volume`.

15. **Emissão de estado (loop 33 ms)** — `TimelineCompositionController.kt:338` → `emitState`
    Lê `currentPosition`, calcula `segmentIndex` via busca linear reversa em `segments`, monta o mapa e chama `eventSink?.success(map)` com:
    `globalPosition`, `clipIndex`, `localPosition`, `isPlaying`, `totalDuration`, `clipDurationsMs`, `canUndo`, `canRedo`.

---

### D. Comandos de edição (com undo/redo)

Cada operação de edição segue o mesmo padrão:

16. **`pushEditSnapshot`** — `TimelineCompositionController.kt:373`
    Antes de mutar `clips` ou `audioTrack`, salva o estado atual em `TimelineEditModel.pushSnapshot`. Isso limpa o `redoStack`.

17. **Mutação da lista de clipes** — exemplos:
    - `trimClip`: copia o `TimelineClip` com novos `trimStartMs`/`trimEndMs`.
    - `splitClip`: calcula `absSplitMs = effectiveTrimStart + atLocalPositionMs`, produz `clipA` e `clipB` e substitui o original por dois no slice.
    - `insertClip`: chama `resolveClip` no novo clipe antes de inserir.
    - `removeClip`, `moveClip`, `replaceClip`, `setClipSpeed`, `setClipAlignment`: variações diretas sobre `clips[index].copy(...)`.
    - `setAudioTrack` / `removeAudioTrack`: altera `audioTrack`.

18. **`rebuildCompositionPreservingPlayback`** — `TimelineCompositionController.kt:322`
    - Recalcula `segments` e `totalDurationMs` via `rebuildSegments`.
    - Captura `positionMs` e `wasPlaying` do player atual.
    - `player.setComposition(buildTimelineComposition(...), positionMs)` aplica a nova composição com seek clampado.
    - `player.prepare()` reinicia o pipeline interno Media3.
    - Se `wasPlaying`, volta a chamar `player.play()`.
    - `emitState()` publica o novo estado.

19. **`undo` / `redo`** — `TimelineCompositionController.kt:266,274`
    - Chama `editHistory.undo(currentSnapshot)` ou `editHistory.redo(currentSnapshot)`.
    - `TimelineEditModel` remove o topo da pilha correspondente, empurra o snapshot atual na pilha oposta (com clampe em 50 entradas) e retorna o snapshot a restaurar.
    - `restoreEditSnapshot` repõe `clips` e `audioTrack` e chama `rebuildCompositionPreservingPlayback`.

---

### E. Exportação

#### E1. `exportTimeline` (clipes brutos sem player ativo)

20. **Dart envia `exportTimeline`** — `VideoUltraPlayerPlugin.kt:301` → `exportTimeline`
    Extrai `clips`, `outputPath` e `config`. Cria um `TimelineCompositionExporter`.

21. **`TimelineCompositionExporter.export`** — `TimelineCompositionController.kt:422`
    Parseia clips, calcula `outputSize`, chama `exportFromClips`.

#### E2. `exportCurrentTimeline` (estado do controller ativo)

22. **Dart envia `exportCurrentTimeline`** — `VideoUltraPlayerPlugin.kt:366` → `exportCurrentTimeline`
    Localiza o controller pelo `textureId`, chama `controller.startExportCurrentTimeline(outputPath, callback)`.

23. **`TimelineCompositionController.startExportCurrentTimeline`** — `TimelineCompositionController.kt:282`
    Copia `clips`, `renderSize` e `audioTrack` do estado atual (snapshot imediato) e cria um `TimelineCompositionExporter` que chama `exportFromClips`.

#### E3. Exportação comum

24. **`exportFromClips`** — `TimelineCompositionController.kt:440`
    - Cria o arquivo de output (path fornecido ou `cacheDir/video_ultra_player_export_<uuid>.mp4`).
    - Chama `buildTimelineComposition` com os mesmos helpers do preview.
    - Cria `Transformer` via `Transformer.Builder(context).addListener(...)`.
    - `transformer.start(composition, outputFile.absolutePath)`.
    - `mainHandler.post(progressRunnable)` inicia polling de progresso a 100 ms via `transformer.getProgress(ProgressHolder)`.

25. **Progresso** — `ExportProgressStreamHandler.emit` → EventChannel `export`
    `onProgress` chama `exportProgressHandler.emit(progress, "exporting")` que faz `eventSink?.success(map)`.

26. **Conclusão** — `Transformer.Listener.onCompleted`
    `complete { callback.onCompleted(outputFile.absolutePath) }` → `result.success(outputPath)` no Dart.

---

### F. Geração de thumbnails

27. **Dart envia `generateThumbnails`** — `VideoUltraPlayerPlugin.kt:406`
    Extrai `videoPath`, `timestampsMs` e `width` (padrão 120 px). Submete ao `thumbnailExecutor` (thread pool cached).

28. **`ThumbnailGenerator.generate`** — `ThumbnailGenerator.kt:31`
    Abre um `MediaMetadataRetriever`, itera sobre `timestampsMs` chamando `generateFrame` para cada timestamp.

29. **Cache e extração** — `ThumbnailGenerator.kt:46` → `generateFrame`
    - Chave de cache: `djb2(videoPath)_${tsMs}_${width}.jpg` em `cacheDir/vup_thumbs/`.
    - Cache hit: retorna o path direto.
    - Cache miss (API ≥ 27): `getScaledFrameAtTime(timeUs, OPTION_CLOSEST_SYNC, width, scaledHeight)`.
    - Cache miss (API 24–26): `getFrameAtTime` + `Bitmap.createScaledBitmap`.
    - Comprime o bitmap como JPEG 80% e persiste no arquivo de cache.

30. **Retorno ao main thread** — `VideoUltraPlayerPlugin.kt:431`
    `mainHandler.post { result.success(paths) }` devolve a lista de paths para o Dart.

---

### G. Dispose

31. **Dart envia `dispose`** — `VideoUltraPlayerPlugin.kt:221`
    Remove o controller de `controllers` e chama `controller.dispose()`.

32. **`TimelineCompositionController.dispose`** — `TimelineCompositionController.kt:300`
    Marca `disposed = true`, remove `stateRunnable` do handler, faz `player.release()`, `surface.release()` e `textureEntry.release()` em ordem.

---

### Caminhos alternativos

- **Argumentos inválidos (qualquer método):** `withController` ou os handlers diretos retornam `result.error("invalid_arguments", ...)` antes de tocar o controller.
- **`textureId` não encontrado:** `withController` retorna `result.error("not_found", ...)`.
- **`load` falha (path inválido, arquivo corrompido):** A exceção propagada por `TimelineCompositionController.load` é capturada em `VideoUltraPlayerPlugin.load` e retorna `result.error("load_failed", ...)`.
- **Erro de playback:** `Player.Listener.onPlayerError` propaga a mensagem (com chain de causas até 5 níveis) via `eventSink.error("playback_error", ...)`.
- **Exportação falha:** `Transformer.Listener.onError` apaga o arquivo de output parcial, emite `"failed"` no canal de progresso e chama `result.error("export_failed", ...)`.
- **Plugin detachado:** `onDetachedFromEngine` cancela todos os exportadores em `activeExporters`, dispõe todos os controllers, desliga `thumbnailExecutor` e remove todos os handlers.

---

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Plugin / Dispatcher | `VideoUltraPlayerPlugin.kt` | Ponto de entrada `FlutterPlugin`; registra canais, mapeia textureId→controller, despacha method calls |
| Controller de playback | `TimelineCompositionController.kt` (classe `TimelineCompositionController`) | Estado do player, SurfaceTexture, loop de estado, operações de edição, undo/redo |
| Exportação | `TimelineCompositionController.kt` (classe `TimelineCompositionExporter`) | Wraps Media3 `Transformer`, polling de progresso, gestão de arquivo de output |
| Builders de composição | `TimelineCompositionController.kt` (funções top-level) | `buildTimelineComposition`, `editedMediaItemFor`, `audioSequenceFor`, `effectsFor`, `resolveClip`, etc. |
| Modelos de dados | `TimelineCompositionController.kt` (data classes) | `TimelineClip`, `AudioTrackDescriptor`, `TimelineCompositionConfig`, `TimelineRenderSize`, `TimelineSegment` |
| Histórico de edição | `TimelineEditModel.kt` | Pilhas de undo/redo com limite de 50 snapshots |
| Thumbnails | `ThumbnailGenerator.kt` | Extração de frames com `MediaMetadataRetriever` e cache JPEG em disco |
| Progresso de export | `VideoUltraPlayerPlugin.kt` (inner class `ExportProgressStreamHandler`) | `EventChannel.StreamHandler` que emite `{progress, state}` no canal `export` |

---

## Regras de Negócio Relevantes

- **Dimensões pares obrigatórias** — `TimelineCompositionController.kt:792` (`evenDimension`): Media3 exige que largura e altura do output sejam pares; qualquer valor ímpar é incrementado.
- **`durationUs` = duração da fonte completa (não trimada)** — `TimelineCompositionController.kt:556`: Media3 valida que `clippingEndPositionMs * 1000 <= durationUs`; usar a duração trimada causa crash quando `trimStartMs > 0`.
- **Speed range 0.5×–2.0×** — `TimelineCompositionController.kt:241` e `TimelineClip.from`: velocidade fora da faixa é clampada silenciosamente.
- **`setComposition` apenas em commit** — `TimelineCompositionController.kt:237` (comentário): `rebuildCompositionPreservingPlayback` é custoso (pipeline full rebuild); chamá-lo em cada tick de drag UI causaria artefatos. A API expõe isso para o caller respeitar.
- **Trilha de áudio externa ignorada se offset ≥ duração total** — `TimelineCompositionController.kt:533`: sequência de áudio é adicionada somente se `audioTrack.offsetMs < timelineDurationMs`.
- **Aspect ratio `ORIGINAL` usa dimensões do primeiro clipe** — `TimelineCompositionController.kt:785`: se nenhum preset de aspect ratio é especificado, o render size é derivado do primeiro clipe da timeline (já com dimensões pares).
- **Undo/redo limita 50 snapshots** — `TimelineEditModel.kt:11`: snapshots além do limite são descartados do início da pilha.
- **Cache de thumbnails por djb2 + timestamp + width** — `ThumbnailGenerator.kt:51`: a mesma combinação de path, timestamp e largura nunca é reprocessada enquanto o arquivo de cache existir em disco.

---

## Dependências Externas

- `androidx.media3:media3-transformer` — `Transformer`, `CompositionPlayer`, `EditedMediaItem`, `EditedMediaItemSequence`, `Composition`, `Effects`, `Presentation`, `Crop`, `GainProcessor`.
- `androidx.media3:media3-common` — `MediaItem`, `Player`, `PlaybackException`, `C`, `SpeedProvider`.
- `android.media.MediaMetadataRetriever` — leitura de metadados (duração, dimensões, rotação) e extração de frames.
- `io.flutter.embedding.engine.plugins.FlutterPlugin` — contrato de plugin federado; `TextureRegistry` para alocar `SurfaceTexture`.
- `io.flutter.plugin.common.MethodChannel` / `EventChannel` — comunicação bidirecional com o Dart.

---

## Observações

- **`withController` é o único guardião de `textureId`** — `VideoUltraPlayerPlugin.kt:435`: todos os comandos que precisam de um controller ativo passam por esse helper. Comandos que não precisam de controller (`load`, `exportTimeline`, `generateThumbnails`, `dispose`) fazem sua própria validação inline.
- **`exportCurrentTimeline` vs `exportTimeline`**: o primeiro exporta o estado atual do controller (clipes editados em memória); o segundo aceita uma lista de clipes brutos independente de qualquer player ativo. São caminhos diferentes no plugin, ambos terminando em `exportFromClips`.
- **Loop de estado nunca para enquanto o controller existe** — `stateRunnable` se agenda de novo em cada tick enquanto `!disposed`; só é interrompido por `dispose()`.
- **`activeExporters` é um `Set` no plugin, não no controller** — garante que `onDetachedFromEngine` possa cancelar todas as exportações em andamento mesmo que o controller correspondente já tenha sido descartado.
- **`splitClip` apaga `transitionToNextMs` do clipA** — `TimelineCompositionController.kt:189`: ao dividir, o ponto de corte não herda a transição original do clip pai para evitar sobreposição incorreta no boundary do split.
- **Crop com clamp de segurança** — `TimelineCompositionController.kt:643–648`: `Crop` exige `left < right` e `bottom < top`; o código garante margens de 0.01f para evitar composições inválidas com scale extremo.

---

*Relacionados: [[native-timeline-player]] (visão geral Dart + iOS + Android), [[project-structure]]*

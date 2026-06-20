# Flow: Camada Nativa iOS

> **Resumo:** Implementação Swift que recebe comandos do Flutter via MethodChannel, monta uma composição AVFoundation de clipes de vídeo/imagem, serve frames em tempo real como Flutter Texture e exporta a timeline como MP4.

## Visão Geral

O ponto de entrada é `VideoUltraPlayerPlugin`, registrado pelo runtime de plugin Flutter em `register(with:)`. O plugin mantém um dicionário `[Int64: TimelinePlayerController]` por `textureId` e roteia todos os 22 comandos do MethodChannel para o controller correspondente. Há dois EventChannels separados: um para estado de playback (por textura) e outro para progresso de exportação (global).

Quando o Flutter chama `load`, o plugin parseia os descritores de clipes e configuração, cria um `TimelinePlayerController` que internamente instancia três colaboradores: `TimelineComposition` (monta `AVMutableComposition`), `TimelineTexture` (expõe frames via `FlutterTextureRegistry`) e `TimelineEditModel` (histórico undo/redo). O `textureId` devolvido identifica o controller em todas as chamadas subsequentes.

Comandos de edição (trim, split, insert, remove, move, replace, setClipSpeed, setAudioTrack) seguem um padrão uniforme: salvar snapshot no `TimelineEditModel`, mutar o modelo de clipes na `TimelineComposition`, reconstruir o `AVPlayerItem` preservando posição e estado de reprodução via `rebuildPreservingPlayback`. `setClipAlignment` é a exceção — atualiza apenas o `AVVideoComposition` inline, sem interromper o player.

A renderização em tempo real usa `CADisplayLink` na thread principal: a cada frame de tela, `TimelineTexture` consulta `AVPlayerItemVideoOutput` pelo pixel buffer do instante atual e notifica o Flutter via `textureRegistry.textureFrameAvailable`. O Flutter então chama `copyPixelBuffer()` na thread do rasterizador.

`ThumbnailGenerator` é um singleton independente que usa `AVAssetImageGenerator` em background para extrair frames e cacheia os JPEGs em disco.

## Passo a Passo

### Registro e Load

1. **Plugin** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `register(with:)`
   Cria a instância com `FlutterTextureRegistry` via `registrar.textures()`. Registra `FlutterMethodChannel` (`video_ultra_player/timeline_player`), `FlutterEventChannel` de estado (`video_ultra_player/timeline_player/events`) e `FlutterEventChannel` de progresso de exportação (`video_ultra_player/timeline_player/export`). O plugin implementa `FlutterStreamHandler` para o canal de estado; `TimelineExportProgressStreamHandler` gerencia o canal de exportação.

2. **Plugin** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `handle(_:result:)` → `"load"` → `load(_:result:)`
   Extrai `clips` (array de dicts) e `config` (dict opcional) dos argumentos. Parseia cada dict em `TimelineClipDescriptor`; qualquer dict inválido retorna `FlutterError(code: "invalid_clip")`. Parseia `TimelineCompositionConfig` com fallback para aspect ratio `original` e `baseWidth` 1080.

3. **Controller init** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController.init`
   Chama `TimelineComposition.build(clips:config:)` para obter um `AVPlayerItem`. Cria `TimelineTexture(playerItem:textureRegistry:)` — o output é adicionado ao item **antes** de entregar ao player. Instancia `AVPlayer(playerItem:)`. Registra a textura com `textureRegistry.register(tex)` obtendo o `textureId`. Chama `tex.start()` para ativar o `CADisplayLink`. Configura observers de tempo e fim de reprodução via `addObservers()`. Configura KVO one-shot para o primeiro frame via `observeInitialItemReady(_:)`.

4. **Composição** — `ios/Classes/TimelineComposition.swift` → `build(clips:config:audioTrack:)`
   Para cada clipe: chama `resolvedAsset(for:)` (vídeos usam `AVURLAsset` direto; imagens geram MP4 temporário via `makeImageVideo`). Calcula `effectiveRange` aplicando `trimStartMs`/`trimEndMs` clampados pela duração do asset. Insere segmentos em único `AVMutableCompositionTrack` de vídeo; aplica `scaleTimeRange` para velocidade. Se algum clipe tem áudio, cria um track de áudio e insere/escalona. Constrói `TimelineSegment` com duração escalada para cada clipe. Se há `AudioTrackDescriptor`, insere trilha externa em track de áudio separado com trim/offset. Chama `makeVideoComposition()` (instruções single-layer por segmento) e `makeAudioMix()` (volumes e fades). Retorna `AVPlayerItem` com composição, `videoComposition` e `audioMix` configurados.

   - **Imagem → vídeo:** `makeImageVideo(from:duration:)` usa `AVAssetWriter` com codec H.264, `AVAssetWriterInputPixelBufferAdaptor` e gera frames a 30 fps. A URL é rastreada em `generatedImageVideoURLs` para limpeza em `dispose()`.

5. **Textura** — `ios/Classes/TimelineTexture.swift` → `init(playerItem:textureRegistry:)` + `start()`
   Cria `AVPlayerItemVideoOutput` com `kCVPixelFormatType_32BGRA` e `kCVPixelBufferIOSurfacePropertiesKey` (obrigatório para o renderer Metal do Flutter). Adiciona o output ao `playerItem`. Em `start()`, cria `CADisplayLink` e adiciona ao RunLoop principal com modo `.common`.

6. **Plugin** — `load(_:result:)` (continuação)
   Salva o controller em `controllers[controller.textureId]` e retorna `controller.textureId` ao Dart.

### Ciclo de Renderização (CADisplayLink)

7. **Textura** — `ios/Classes/TimelineTexture.swift` → `onDisplayLink(_:)`
   Chamado ~60 Hz na thread principal. Converte `displayLink.timestamp` em `itemTime` via `videoOutput.itemTime(forHostTime:)`. Se `hasNewPixelBuffer(forItemTime:)`, copia com `copyPixelBuffer(forItemTime:itemTimeForDisplay:)`, armazena em `pixelBufferCache` (protegido por `bufferLock`) e chama `textureRegistry?.textureFrameAvailable(textureId)`.

8. **Textura** — `ios/Classes/TimelineTexture.swift` → `copyPixelBuffer()`
   Chamado pela thread do rasterizador Flutter. Adquire `bufferLock`, retorna `pixelBufferCache` via `Unmanaged.passRetained` (transfere ownership ao Flutter; rasterizador libera).

### Primeiro Frame ao Pausar

9. **Controller** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `observeInitialItemReady(_:)`
   KVO one-shot em `playerItem.status`. Quando `.readyToPlay`, faz seek para a posição atual com tolerância zero e, na completion, chama `texture.requestFrame()` → `textureRegistry?.textureFrameAvailable(textureId)`. Evita tela preta enquanto pausado.

### Comandos de Playback

10. **Plugin → Controller** — `play`, `pause`, `seekTo`, `seekToClip`, `setVolume`
    Plugin resolve controller via `textureId`. `seekTo` usa `CMTime(value: positionMs, timescale: 1_000)` com tolerância zero. `seekToClip(clipIndex:)` usa `composition.startTime(forClipIndex:)` para obter o `CMTime` de início do segmento. `setVolume` faz `min(max(volume, 0), 1)`. Após cada operação, `emitState()`.

### Emissão de Estado

11. **Controller** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController.emitState()`
    Lê `player.currentTime()`, cruza com `composition.playbackState(at:)` para obter `clipIndex` e `localPosition`. Emite dict: `globalPosition`, `clipIndex`, `localPosition`, `isPlaying` (`player.rate != 0`), `totalDuration`, `clipDurationsMs`, `canUndo`, `canRedo` pelo `eventSink`.

12. **Controller** — timer periódico em `addObservers()`
    `player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30))` chama `emitState()` a cada ~33 ms durante reprodução.

### Comandos de Edição

13. **Plugin → Controller → Composição** — ex. `trimClip`
    Plugin valida args e delega para `controller.trimClip(at:trimStartMs:trimEndMs:)`. Controller: (a) captura `positionMs = player.currentTime().timelineMilliseconds`; (b) chama `pushEditSnapshot()` → `editHistory.pushSnapshot(composition.makeEditSnapshot())`; (c) chama `composition.trimClip(at:trimStartMs:trimEndMs:)` para mutar a lista de clipes; (d) chama `rebuildPreservingPlayback(positionMs:)`.

14. **Controller** — `rebuildPreservingPlayback(positionMs:clearAudioTrack:)`
    Salva `wasPlaying`. Chama `composition.rebuildAsPlayerItem(config:clearAudioTrack:)` → `build(clips:)` com a lista atualizada. Remove observer `.AVPlayerItemDidPlayToEndTime` do item antigo. Chama `texture.replacePlayerItem(newItem)` (adicionar output ao novo item o desconecta do anterior automaticamente) e `player.replaceCurrentItem(with:newItem)`. Adiciona observer ao novo item. Faz seek para `positionMs`, retoma se `wasPlaying` e emite estado.

15. **Composição** — caso especial `setClipAlignment`
    `controller.setClipAlignment(clipIndex:x:y:)` chama `composition.updateAlignment(clipIndex:x:y:)`, que atualiza `clips[index].alignmentX/Y` (clampados em `[-1, 1]`) e recalcula `makeVideoComposition()`. O controller aplica via `player.currentItem?.videoComposition = videoComposition`. Não chama `rebuildPreservingPlayback`; o player continua sem interrupção.

### Undo/Redo

16. **Controller** — `undo()` / `redo()`
    Cria snapshot atual via `composition.makeEditSnapshot()`, chama `editHistory.undo(current:)` / `editHistory.redo(current:)`. Se há snapshot anterior, chama `composition.restoreEditSnapshot(snapshot)` e `rebuildPreservingPlayback`.

17. **EditModel** — `ios/Classes/TimelineEditModel.swift` → `pushSnapshot` / `undo` / `redo`
    Pilhas LIFO separadas para undo e redo, limite de 50 entradas. `pushSnapshot` limpa `redoStack` incondicionalmente. `undo` move snapshot do topo do undoStack → redoStack e devolve o anterior. `redo` faz o inverso.

### Exportação

18. **Plugin** — `exportTimeline`
    Parseia `clips` e `config` dos argumentos, resolve `outputPath` ou gera nome único em `FileManager.temporaryDirectory`. Cria nova `TimelineComposition()`, chama `composition.buildExportAsset(clips:config:)` que internamente chama `build(clips:)` e empacota asset + videoComposition + audioMix em `TimelineExportAsset`. Delega para `runExportSession`.

19. **Plugin** — `exportCurrentTimeline`
    Usa controller existente. Chama `controller.buildCurrentExportAsset()` → `composition.buildCurrentExportAsset(config:)` (reutiliza `self.clips` e `currentAudioTrack` ativos). Delega para `runExportSession`.

20. **Plugin** — `runExportSession(asset:outputURL:onDispose:result:)`
    Cria `AVAssetExportSession` com preset `AVAssetExportPresetHighestQuality`. Configura `outputURL`, `outputFileType = .mp4`, `shouldOptimizeForNetworkUse = true`, `videoComposition` e `audioMix`. Emite `state: "exporting"` via `exportProgressHandler`. Inicia `Timer` de 0,1s para polling de `exporter.progress`. Chama `exporter.exportAsynchronously`. Na completion (main thread): invalida timer, chama `onDispose?()`, emite `state: "completed"` e retorna path, ou `state: "failed"` e `FlutterError(code: "export_failed")`.

### Geração de Thumbnails

21. **Plugin** — `generateThumbnails`
    Valida `videoPath`, `timestampsMs` e `width`. Delega para `ThumbnailGenerator.shared.generate(videoPath:timestampsMs:width:completion:)`. Na completion, chama `DispatchQueue.main.async` antes de passar o array de paths para `result`.

22. **ThumbnailGenerator** — `ios/Classes/ThumbnailGenerator.swift` → `generate`
    Executa em `DispatchQueue.global(qos: .userInitiated)`. Cria `AVURLAsset` e `AVAssetImageGenerator` com `appliesPreferredTrackTransform = true` e tolerância zero (`requestedTimeToleranceBefore/After = .zero`). Para cada timestamp: verifica cache em `vup_thumbs/{djb2(videoPath)}_{tsMs}_{width}.jpg`; se não existe, extrai frame com `copyCGImage(at:actualTime:)`, escala para `width` com `UIGraphicsImageRenderer` (mantendo aspect ratio) e salva JPEG com qualidade 0,8. Frames sem extração são silenciosamente omitidos da lista de retorno.

### Dispose

23. **Plugin → Controller → Textura + Composição**
    O plugin remove o controller de `controllers`, chama `controller.dispose()`: anula `firstFrameObserver`, remove `timeObserver` do player, remove observer de `AVPlayerItemDidPlayToEndTime`, pausa o player, chama `texture.dispose()` (invalida `CADisplayLink`, limpa `pixelBufferCache`), chama `textureRegistry.unregisterTexture(textureId)`, chama `composition.dispose()` (remove arquivos MP4 temporários de imagens).

### Caminhos Alternativos

- **Clips inválidos no load:** `clips(from:result:)` retorna `FlutterError(code: "invalid_arguments")` se faltam os campos obrigatórios de algum clipe.
- **`textureId` não encontrado:** `controller(for:result:)` retorna `FlutterError(code: "not_found")`.
- **Composição vazia:** `build()` lança `TimelineCompositionError.emptyClips` antes de criar qualquer track.
- **Vídeo sem track de vídeo:** `build()` lança `TimelineCompositionError.missingVideoTrack(path)`.
- **Imagem inválida:** `resolvedAsset` lança `TimelineCompositionError.invalidClip` se `UIImage(contentsOfFile:)` retorna nil.
- **Composição sem áudio:** nenhum track de áudio é criado; `makeAudioMix()` retorna `nil`; `playerItem.audioMix` fica nil.
- **Trim além do asset:** `effectiveRange` clampeia com `CMTimeMinimum(requestedDuration, asset.duration - trimStart)`.
- **Speed fora de [0.5, 2.0]:** clampado no parse de `TimelineClipDescriptor` e em `setClipSpeed`.
- **Export cancelado/falhou:** `exporter.status == .cancelled` ou `.failed` → `FlutterError(code: "export_failed")` com `exporter.error?.localizedDescription` como `details`.
- **Thumbnail sem frame extraível:** `copyCGImage` lança; o path não é adicionado ao array (lista pode ter menos entradas que `timestampsMs`).
- **Seek após rebuild:** seek com tolerância zero pode retornar ligeiramente antes do frame exato; é aceito como tradeoff de precisão.
- **EventSink ausente:** `emitState()` é no-op se `eventSink == nil` (stream não assinado ou já cancelado).

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Plugin / roteador | `ios/Classes/VideoUltraPlayerPlugin.swift` | Registra channels, gerencia `[textureId → controller]`, roteia 22 comandos, exporta MP4 com polling de progresso, implementa `FlutterStreamHandler` para estado por textura. |
| Controller (privado) | `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController` | Orquestra `AVPlayer`, `TimelineComposition`, `TimelineTexture` e `TimelineEditModel`; implementa padrão edit-snapshot-rebuild para cada mutação; emite estado periódico. |
| Export progress handler (privado) | `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelineExportProgressStreamHandler` | Stream handler dedicado para progresso de exportação; emite `{progress, state}` durante e após `AVAssetExportSession`. |
| Composição | `ios/Classes/TimelineComposition.swift` | Monta `AVMutableComposition` (1 video track, 1 audio track opcional, 1 external audio track opcional); aplica trim, speed, imagens como vídeo temporário, `AVVideoComposition` single-layer e `AVAudioMix` com fades. Define `TimelineClipDescriptor`, `TimelineCompositionConfig`, `TimelineSegment`, `AudioTrackDescriptor` e `TimelineExportAsset`. |
| Textura | `ios/Classes/TimelineTexture.swift` | Liga `AVPlayerItemVideoOutput` ao `FlutterTexture`; usa `CADisplayLink` para capturar frames e `NSLock` para entrega thread-safe ao rasterizador Flutter. |
| Histórico de edição | `ios/Classes/TimelineEditModel.swift` | Pilhas LIFO de `TimelineEditSnapshot` (clips + audioTrack) com limite de 50 entradas; undo/redo por troca de snapshots. |
| Gerador de thumbnails | `ios/Classes/ThumbnailGenerator.swift` | Singleton com cache em disco (`vup_thumbs/`, chave djb2); extrai frames com `AVAssetImageGenerator` em background e salva JPEGs escalados. |

## Regras de Negócio Relevantes

- **Snapshot antes de cada mutação** — `TimelinePlayerController.pushEditSnapshot()`: chamado imediatamente antes de qualquer mutação de `TimelineComposition`, garantindo que undo sempre exista.
- **Rebuild preserva posição e playback** — `rebuildPreservingPlayback`: captura `positionMs` e `wasPlaying`; faz seek e retoma reprodução após `replaceCurrentItem`.
- **Alinhamento não reconstrói** — `setClipAlignment` aplica novo `AVVideoComposition` inline; é o único comando de edição que não chama `rebuildPreservingPlayback`.
- **Primeiro frame exige seek explícito** — `AVPlayerItemVideoOutput` não entrega frames enquanto pausado sem um seek; `observeInitialItemReady` dispara esse seek ao detectar `.readyToPlay`.
- **Video output adicionado antes do AVPlayer** — ordem no `TimelinePlayerController.init` garante que o output faça parte do pipeline desde o primeiro frame.
- **`copyPixelBuffer` usa `passRetained`** — ownership transferido ao Flutter; não usar `passUnretained` pois o rasterizador pode usar o buffer após o display link substituí-lo.
- **Imagens geram MP4 temporário** — `makeImageVideo` bloqueia (usa `DispatchSemaphore`) e deve ser chamado fora da main thread para evitar deadlock; na prática é chamado no `load` que vem do MethodChannel em thread de background.
- **Redo é limpo em nova edição** — `pushSnapshot` chama `redoStack.removeAll()` incondicionalmente.
- **Duração de segmentos é a duração escalada** — `TimelineSegment.duration = scaledVideoDuration`; `totalDuration`, `clipDurationsMs` e `playbackState` usam tempos de composição, não tempos de source.
- **Áudio externo tem fallback de duração** — se `trimEndMs` não é informado, a duração é `totalDuration - offsetMs`; clampado para não ultrapassar a timeline.
- **`volume NaN` vira 1.0** — `makeAudioMix` usa `descriptor.volume.isNaN ? 1.0 : max(0, min(descriptor.volume, 1))`.
- **Thumbnails omitem frames não extraíveis** — a lista retornada pode ter menos elementos que `timestampsMs`; o caller deve lidar com índices não correspondentes.

## Dependências Externas

- **AVFoundation** — `AVMutableComposition`, `AVPlayer`, `AVPlayerItem`, `AVPlayerItemVideoOutput`, `AVVideoComposition`, `AVAudioMix`, `AVAssetWriter`, `AVAssetExportSession`, `AVAssetImageGenerator`, `AVURLAsset`
- **Flutter.framework** — `FlutterPlugin`, `FlutterTexture`, `FlutterTextureRegistry`, `FlutterMethodChannel`, `FlutterEventChannel`, `FlutterEventSink`, `FlutterStreamHandler`
- **QuartzCore** — `CADisplayLink` para sincronização com o display
- **UIKit** — `UIImage`, `UIGraphicsImageRenderer`, `UIGraphicsPushContext` (rendering de imagens em pixel buffer)

## Observações

- O campo `transitionToNextMs` é parseado em `TimelineClipDescriptor` mas não é usado em `build(clips:config:)` — a composição atual faz hard cuts. É uma preparação para crossfade futuro.
- `TimelineTexture` contém código de diagnóstico com `NSLog` e a flag `_didCaptureFirstFrame` marcada com "remove when fixed" — deve ser removido após validação do primeiro frame.
- `replacePlayerItem` em `TimelineTexture` aproveita o comportamento implícito do `AVPlayerItemVideoOutput`: adicionar o output a um novo item o desconecta do anterior automaticamente.
- A exportação faz polling a cada 100 ms via `Timer` porque `AVAssetExportSession` não oferece callback de progresso nativo.
- `ThumbnailGenerator.generate` é chamado com `completion` na thread de background; o plugin faz `DispatchQueue.main.async` antes de chamar `result`, respeitando o requisito do Flutter de responder no main thread.
- A instância default de `VideoUltraPlayerPlugin` (criada por `public override init()`) tem `textureRegistry = nil` e retornará `FlutterError(code: "not_attached")` em qualquer chamada a `load` — apenas a instância criada por `register(with:)` é funcional.

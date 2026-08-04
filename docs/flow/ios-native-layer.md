---
generated_at: 2026-07-31
source_commit: b234395
source_state: clean
verified_at: 2026-08-02
status: current
related_plans:
  - docs/plan/onda-1-quick-wins.md
  - docs/plan/onda-2-identidade-editor.md
  - docs/plan/text-overlays/00-indice.md
---

# Flow: Camada Nativa iOS

> **Resumo:** Implementação Swift que recebe os comandos do MethodChannel, monta uma `AVMutableComposition` com todos os clipes, serve os frames dessa composição como `FlutterTexture` e exporta o mesmo estado como MP4.

## Visão Geral

O ponto de entrada é `VideoUltraPlayerPlugin.register(with:)`, que cria a instância com o `FlutterTextureRegistry` do registrar e liga três canais: o `FlutterMethodChannel` de comandos, o `FlutterEventChannel` de estado (o próprio plugin é o `FlutterStreamHandler`) e o `FlutterEventChannel` de progresso de export, cujo handler é o `TimelineExportProgressStreamHandler` privado.

O plugin guarda `controllers: [Int64: TimelinePlayerController]` e roteia cada método por `switch call.method`. Comandos de player extraem o `textureId` dos argumentos e resolvem o controller via `controller(for:result:)`; `generateThumbnails` e `exportTimeline` não precisam de controller.

Em `load`, o plugin monta os `TimelineClipDescriptor` e instancia `TimelinePlayerController`, que faz três coisas na ordem certa: pede à `TimelineComposition` um `AVPlayerItem` pronto, cria o `TimelineTexture` **antes** de entregar o item ao `AVPlayer` (o `AVPlayerItemVideoOutput` precisa estar no pipeline desde o primeiro frame) e registra a textura, guardando o id devolvido. Em seguida instala o `addPeriodicTimeObserver` (1/30 s), o observer de `AVPlayerItemDidPlayToEndTime` e um KVO one-shot em `status` que força o primeiro frame com um seek de tolerância zero.

A composição em si é responsabilidade de `TimelineComposition.build`. Ela prepara cada clipe (`PreparedClip`) resolvendo o asset — imagens são convertidas em MP4 temporário por `makeImageVideo` usando `AVAssetWriter`, com cache por path — calcula a janela efetiva de trim, insere o range na única trilha de vídeo e aplica `scaleTimeRange` para obter a velocidade pedida. O áudio dos clipes vai para uma segunda trilha, criada **somente** se algum clipe tiver áudio, e é escalado separadamente porque sua duração de fonte pode divergir da do vídeo. Cada clipe inserido gera um `TimelineSegment` com a duração já escalada, o que mantém `totalDuration`, `seekToClip`, `clipDurationsMs` e `playbackState` coerentes. Por fim, a trilha de áudio externa (se houver) entra como uma terceira trilha, o `AVAudioMix` é montado com volumes e ramps, e o `AVMutableVideoComposition` recebe uma instrução por segmento com o transform de cover-crop calculado a partir de `preferredTransform`, `renderSize`, `scale` e `alignment`.

Edição segue um padrão único: `pushEditSnapshot()` → mutação no modelo de clipes da `TimelineComposition` → `rebuildPreservingPlayback(positionMs:)`, que reconstrói o `AVPlayerItem` do zero, move o `AVPlayerItemVideoOutput` para o novo item, troca o item no player, refaz o observer de fim e faz seek para a posição salva, retomando o play se estava tocando. `setClipAlignment` é a exceção original: só recalcula o `AVVideoComposition` e o atribui ao item atual, sem rebuild. Text overlays adotam esse mesmo padrão cirúrgico via `applyUpdatedVideoComposition()` (snapshot → mutar `textOverlays` → re-gerar só a videoComposition → reatribuir; seek de tolerância zero + `requestFrame` se pausado) — os textos queimados vivem no `animationTool` da própria videoComposition, então preview e export compartilham o mesmo caminho de renderização em `makeVideoComposition()`.

`ThumbnailGenerator` é um singleton independente do player: extrai frames com `AVAssetImageGenerator` em fila global e cacheia JPEGs em `NSTemporaryDirectory()/vup_thumbs/`.

## Passo a Passo

1. **Registro** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `register(with:)`
   Instancia o plugin com `registrar.textures()`, registra o method channel como delegate e os dois event channels com seus handlers.
2. **Roteamento** — `handle(_:result:)`
    `switch call.method` sobre `load`, `exportTimeline`, `exportCurrentTimeline`, `play`, `pause`, `seekTo`, `seekToClip`, `setVolume`, `setClipAlignment`, `trimClip`, `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip`, `setClipSpeed`, `setCompositionConfig`, `undo`, `redo`, `setAudioTrack`, `removeAudioTrack`, `addTextOverlay`, `updateTextOverlay`, `removeTextOverlay`, `generateThumbnails`, `dispose`; qualquer outro cai em `FlutterMethodNotImplemented`. Os cases de texto parseiam `args["overlay"]` com `TextOverlayDescriptor(dictionary:)` e respondem `invalid_arguments` quando o parse falha.
3. **Parsing de entrada** — `clips(from:result:)` + `TimelineClipDescriptor(dictionary:)` + `TimelineCompositionConfig(dictionary:)`
   `speed` é clampado em `[0.5, 2.0]` e `scale` tem mínimo `0.01` já no parse.
4. **Criação do controller** — `TimelinePlayerController.make(clips:config:textureRegistry:completion:)`
   **Assíncrono, fora da thread da plataforma.** `composition.build(...)` roda na `buildQueue` (serial, `qos: .userInitiated`) porque ler as trilhas de origem e rasterizar stills bloqueia; só a segunda metade volta para a main thread, onde a textura precisa ser registrada: `TimelineTexture(playerItem:textureRegistry:)` → `AVPlayer(playerItem:)` → `textureRegistry.register(tex)` → `tex.start()` → `addObservers()` → `observeInitialItemReady(playerItem)`. O `load` do plugin responde pelo `completion`.
5. **Preparação dos clipes** — `ios/Classes/TimelineComposition.swift` → `resolvedAsset(for:)` / `effectiveRange(for:asset:)`
   Vídeo vira `AVURLAsset` direto; imagem vira MP4 servido pelo `ImageClipVideoCache` (cache de processo, chaveado por path + mtime + tamanho + duração), que só encoda quando não há hit. Sem trilha de vídeo no asset, lança `missingVideoTrack`.
6. **Montagem da composição** — `TimelineComposition.build`
   Insere cada range na trilha de vídeo, aplica `scaleTimeRange` para a speed, insere e escala o áudio do clipe quando existe, e acumula `TimelineSegment` + `totalDuration`.
7. **Áudio externo e mix** — `TimelineComposition.build` (bloco `currentAudioTrack`) + `makeAudioMix`
   Insere a trilha externa no `offsetMs` com clamp pelo tempo restante da timeline e aplica volume, fade-in e fade-out via `setVolumeRamp`.
8. **Composição de vídeo** — `makeVideoComposition` → `singleLayerInstruction` → `layerInstruction` → `transform(for:)`
    Uma instrução por segmento, ordenada por tempo; o transform faz cover-crop usando `coverScale * clip.scale` e desloca conforme `alignment`. Quando `textOverlays` não está vazio, o final do método anexa `videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)`, com a árvore de textos por cima do vídeo.
9. **Textura** — `ios/Classes/TimelineTexture.swift` → `init` / `start` / `onDisplayLink` / `copyPixelBuffer`
   `AVPlayerItemVideoOutput` com `kCVPixelFormatType_32BGRA` + `IOSurfaceProperties`; o `CADisplayLink` mapeia `hostTime → itemTime`, copia o buffer sob `NSLock` e chama `textureFrameAvailable`.
10. **Estado** — `TimelinePlayerController.emitState`
    Cruza `player.currentTime()` com `composition.playbackState(at:)` e monta um `EmittedState`; só emite quando ele difere do último. Sem essa deduplicação o observer periódico (1/30) empurraria 30 mensagens idênticas por segundo com o player pausado. Trocar o `eventSink` zera o último estado para que o primeiro `emitState` sempre passe.
11. **Edição** — `trimClip` / `splitClip` / `insertClip` / `removeClip` / `moveClip` / `replaceClip` / `setClipSpeed` / `setAudioTrack` / `removeAudioTrack`
    Guardam a posição atual, chamam `pushEditSnapshot()`, mutam a composição e chamam `rebuildPreservingPlayback(positionMs:)`.
12. **Undo/redo** — `undo()` / `redo()`
    `composition.makeEditSnapshot()` → `editHistory.undo/redo(current:)` → `restoreEditSnapshot` → rebuild. Pilha vazia é no-op que só re-emite estado.
13. **Alinhamento sem rebuild** — `setClipAlignment(clipIndex:x:y:)`
    `pushEditSnapshot()` + `composition.updateAlignment(...)` e atribuição direta em `player.currentItem?.videoComposition`.
13b. **Resolução/proporção sem rebuild** — `setCompositionConfig(_:)` → `TimelineComposition.updateConfig(_:)`
    Só o `renderSize` e os transforms por segmento dependem da config, então a `AVMutableComposition` (e todas as fontes já abertas) fica intacta: recalcula o `renderSize`, re-gera a videoComposition, reatribui ao item, atualiza o render size dos textos na textura e, se pausado, faz seek de tolerância zero + `requestFrame()`. Não empurra snapshot de edição — config de saída não é undo-ável. Nada é redecodificado e o `textureId` não muda.
14. **Text overlays** — `addTextOverlay` / `updateTextOverlay` / `removeTextOverlay(id:)` → `applyUpdatedVideoComposition()`
    `pushEditSnapshot()` → mutação em `TimelineComposition.textOverlays` → `updatedVideoComposition()` (wrapper de `makeVideoComposition()`) → `player.currentItem?.videoComposition = ...`; se pausado, seek de tolerância zero + `texture.requestFrame()` para o frame pausado refletir o texto. A janela de cada `CATextLayer` é `[AVCoreAnimationBeginTimeAtZero + start, + end)` com `fillMode = .forwards`.
15. **Export** — `exportTimeline` / `exportCurrentTimeline` → `runExportSession`
    `AVAssetExportSession` com preset `HighestQuality`, `videoComposition` e `audioMix` da composição, `Timer` de 0,1 s publicando `exporter.progress` e resultado no `DispatchQueue.main`. O `animationTool` vai embutido na videoComposition exportada por `exportCurrentTimeline`; o `exportTimeline(clips)` standalone monta uma `TimelineComposition` nova, sem overlays.
16. **Thumbnails** — `ios/Classes/ThumbnailGenerator.swift` → `ThumbnailGenerator.shared.generate(...)`
    Fila `.userInitiated`, `AVAssetImageGenerator` com tolerância zero, cache por `hashPath(videoPath)_ts_width.jpg`; o resultado volta para a main thread antes de `result(paths)`.
17. **Dispose** — `TimelinePlayerController.dispose`
    Remove o time observer e os observers de notificação, pausa o player, `texture.dispose()`, `unregisterTexture(textureId)` e `composition.dispose()` (apaga os MP4s temporários de imagem).

### Caminhos alternativos

- **Plugin criado sem registry:** o `init()` público deixa `textureRegistry = nil` e `load` responde `not_attached`.
- **Argumentos ausentes:** `textureId(from:result:)` responde `invalid_arguments`; nos `case` de edição, um `guard` sem `else` explícito faz a chamada retornar sem resposta quando um campo numérico obrigatório falta.
- **Controller inexistente:** `controller(for:result:)` responde `not_found`.
- **Erro de edição:** cada `case` de edição captura o `throw` do controller e responde `edit_failed` com o erro em `details`.
- **Índice fora de faixa:** os métodos de edição do controller e da composição fazem `guard clips.indices.contains(index)` e retornam sem alterar nada.
- **`removeAudioTrack` sem trilha:** apenas re-emite estado, sem rebuild.
- **`updateTextOverlay`/`removeTextOverlay` com id inexistente:** no-op no `TimelineComposition` (busca por `id` não encontra) + re-renderização inócua da mesma composição.
- **Fonte custom inválida:** `TextOverlayLayers.resolveFont` registra via `CTFontManagerRegisterFontsForURL` (erro de re-registro ignorado), resolve o PostScript name e cai em `UIFont.systemFont` — nunca falha o load.
- **Falha de export:** `export_failed` em três pontos — falha ao criar a sessão, status `.failed/.cancelled` e qualquer status inesperado; em todos, o handler de progresso emite `state: "failed"`.
- **Falha na geração do MP4 de imagem:** `cannotCreateImageVideo` / `invalidClip`, propagado como `load_failed`.
- **`onListen` sem `textureId`:** devolve `FlutterError(code: "invalid_arguments")` e o stream não abre.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Plugin / roteamento | `ios/Classes/VideoUltraPlayerPlugin.swift` | Canais, mapa de controllers, parsing de argumentos, export, stream handlers |
| Controller | `ios/Classes/VideoUltraPlayerPlugin.swift` → `TimelinePlayerController` | `AVPlayer`, observers, rebuild preservando playback, emissão de estado |
| Composição | `ios/Classes/TimelineComposition.swift` | Descritores, `AVMutableComposition`, segmentos, `AVVideoComposition`, `AVAudioMix`, estado de `textOverlays`, `updateConfig` |
| Cache de stills | `ios/Classes/ImageClipVideoCache.swift` | Encode imagem→MP4 (6 fps, lado maior ≤ 1920 px) e cache de processo com LRU em disco |
| Textos | `ios/Classes/TextOverlayLayers.swift` | Árvore `CALayer`/`CATextLayer`, resolução de fonte (sistema e `fontPath`), janela `beginTime`/`duration` |
| Textura | `ios/Classes/TimelineTexture.swift` | `AVPlayerItemVideoOutput`, `CADisplayLink`, `copyPixelBuffer` |
| Histórico | `ios/Classes/TimelineEditModel.swift` | `TimelineEditSnapshot` e pilhas undo/redo (limite 50) |
| Thumbnails | `ios/Classes/ThumbnailGenerator.swift` | `AVAssetImageGenerator` + cache em disco |
| Build | `ios/video_ultra_player.podspec` | `source_files = 'Classes/**/*'`, iOS 13.0, Swift 5.0 |
| Contraparte Dart | `lib/video_ultra_player_method_channel.dart` | Nomes de método e chaves esperadas por este código |

## Regras de Negócio Relevantes

- **Trilha de áudio só existe se algum clipe tiver áudio** — `TimelineComposition.build`: o guard `hasAnyClipAudio` evita criar a trilha vazia; sem ele o carregamento falhava silenciosamente (corrigido em 2.0.5 conforme `CHANGELOG.md`).
- **Speed é aplicado com `scaleTimeRange`** — vídeo e áudio são escalados separadamente, e o `TimelineSegment` guarda a duração escalada.
- **`trimEnd` prevalece sobre `duration`** — `effectiveRange`: com `trimEndMs` presente, a duração é `trimEnd - trimStart` clampada pela duração do asset; o mínimo defensivo é 100 ms.
- **Imagem ignora trim** — `effectiveRange` retorna `(.zero, durationMs ?? 2000)`.
- **`split` produz corte seco** — `splitClip` zera `transitionToNextMs` do primeiro pedaço e converte `durationMs` em `trimEndMs` explícito no segundo.
- **`trimClip` descarta `durationMs`** — `clips[index].durationMs = nil`, para que `trimEnd` seja a única fonte de duração.
- **Alinhamento é clampado em `[-1, 1]`** — `updateAlignment`; `transform(for:)` converte para deslocamento proporcional ao overflow do cover-crop.
- **`renderSize` sempre par** — `evenSize` arredonda para cima em ambas as dimensões (requisito dos encoders H.264).
- **Histórico limitado a 50 snapshots** — `TimelineEditModel(limit:)`; `pushSnapshot` limpa a pilha de redo.
- **Um `AVPlayerItemVideoOutput` por item** — `replacePlayerItem` adiciona o output ao novo item, o que automaticamente o desanexa do antigo; por isso a ordem em `rebuildPreservingPlayback` importa.
- **Textos vivem no `animationTool` da videoComposition** — `makeVideoComposition()` é o único ponto de criação e anexa `AVVideoCompositionCoreAnimationTool` quando há overlays; por isso preview e export (`exporter.videoComposition`) queimam os mesmos textos.
- **Janela de texto por `beginTime`/`duration`** — `TextOverlayLayers`: `beginTime = AVCoreAnimationBeginTimeAtZero + startSeconds`, `duration = end - start` clampado pela duração total, `fillMode = .forwards`; `isRemovedOnCompletion` não existe em `CALayer` (é de `CAAnimation`) e o fallback documentado é keyframe de opacity.
- **`fontPath` vence `fontFamily`** — `resolveFont` tenta o arquivo custom primeiro (PostScript name via Core Text) e depois a família de sistema; fallback sempre para `systemFont`.
- **Export usa exatamente o preview** — `buildCurrentExportAsset` reconstrói a partir da mesma lista `clips` e do mesmo `currentConfig` (que `setCompositionConfig` mantém atualizado), então trocar a proporção também muda o MP4 exportado.
- **`load` não bloqueia a thread da plataforma** — `TimelinePlayerController.make` monta a composição na `buildQueue` e só registra a textura na main; qualquer resposta (sucesso ou `load_failed`) chega pelo `completion`.
- **Stills são encodadas uma vez por processo** — `ImageClipVideoCache` guarda o MP4 por path + mtime + tamanho + duração e sobrevive ao `dispose` do controller (`TimelineComposition.dispose()` é no-op). O encode usa 6 fps e limita o lado maior a 1920 px: uma still é estática, então o preview é idêntico por uma fração do custo. O diretório em `tmp` é limpo na primeira utilização do processo, porque o índice em memória começa vazio.
- **Estado é deduplicado antes do canal** — `emitState` compara um `EmittedState` com o anterior e devolve cedo quando nada mudou.
- **Thumbnails são cacheadas por `(path, timestamp, width)`** — `ThumbnailGenerator.generate` devolve o arquivo existente sem re-extrair.

## Dependências Externas

- **AVFoundation:** `AVMutableComposition`, `AVMutableVideoComposition`, `AVMutableAudioMix`, `AVPlayer`, `AVPlayerItemVideoOutput`, `AVAssetWriter`, `AVAssetExportSession`, `AVAssetImageGenerator`.
- **UIKit:** `UIImage`, `UIGraphicsImageRenderer`, `UIGraphicsPushContext` (geração do MP4 de imagem e resize das thumbnails).
- **QuartzCore:** `CADisplayLink`.
- **Flutter iOS embedder:** `FlutterPlugin`, `FlutterTexture`, `FlutterTextureRegistry`, `FlutterStreamHandler`.

## Observações

- `TimelineTexture.onDisplayLink` mantém `NSLog` de diagnóstico até capturar o primeiro frame, com comentário "remove once working" — é ruído em produção.
- `makeImageVideo` roda de forma síncrona na thread do channel: escreve todos os frames do MP4 com `Thread.sleep` de 5 ms enquanto o writer não aceita dados, e bloqueia num `DispatchSemaphore` até `finishWriting`. Para imagens longas isso segura a thread.
- `transitionToNextMs` é parseado do mapa Dart, mas nenhuma instrução de vídeo o usa — não existe crossfade implementado; todo limite entre clipes é corte seco.
- `TimelineEditSnapshot` agora inclui `textOverlays`, então undo/redo restauram textos junto com clipes e áudio; o rebuild completo passa pelo mesmo `makeVideoComposition()`.
- O plugin não implementa `onDetachedFromEngine` (não é `FlutterPlugin` com `detachFromEngine` explícito): os controllers só são liberados pelo `dispose` explícito vindo do Dart.
- `TimelineComposition.moveClip` valida `to <= clips.count - 1` e depois insere em `min(to, clips.count)`, o que difere sutilmente do Android (que valida `toIndex in clips.indices` antes de remover) — o comportamento coincide para os casos válidos.
- Não há teste automatizado desta camada; `example/ios/RunnerTests/RunnerTests.swift` pertence ao app de exemplo.

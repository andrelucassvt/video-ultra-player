---
generated_at: 2026-07-31
source_commit: 21182b1
source_state: clean
verified_at: 2026-08-12
status: current
related_plans:
  - docs/plan/onda-1-quick-wins.md
  - docs/plan/text-overlays/00-indice.md
---

# Flow: Exportação MP4 com Progresso

> **Resumo:** A timeline é codificada em um arquivo MP4 local — a partir da lista de clipes recebida (`exportTimeline`) ou do estado nativo já editado (`exportCurrentTimeline`) — enquanto o progresso é publicado num `EventChannel` dedicado.

## Visão Geral

Há duas portas de export, com contratos diferentes. `exportTimeline(clips)` é independente do player: não exige `load`, monta uma composição nova só para exportar e serve para exportar uma lista de clipes qualquer. `exportCurrentTimeline()` exige `load` e exporta o estado nativo corrente — mesma lista de clipes já editada, mesmo `renderSize`, mesma trilha de áudio externa e **os mesmos text overlays** queimados no preview (iOS via `animationTool` embutido na videoComposition; Android via `OverlayEffect` por clipe). É essa segunda porta que garante a regra "o MP4 é exatamente o que o preview mostra", e é a usada pelo app de exemplo.

Em Dart, `NativeTimelinePlayer` protege as duas com um mutex simples: o campo `_exporting` faz uma segunda chamada concorrente lançar `StateError`, e é liberado num `finally`. O getter `exportProgress` só pode ser acessado enquanto `_exporting` é `true` — fora disso lança `StateError`. O stream vem do `EventChannel` `video_ultra_player/timeline_player/export`, que é **global** (não recebe `textureId`) e emite `{progress, state}` decodificado por `TimelineExportProgress.fromMap` com `progress` clampado em `[0, 1]` e `state` resolvido no enum `TimelineExportState` (fallback `idle`).

No iOS, o plugin resolve o path de saída (o informado ou um arquivo em `temporaryDirectory` com UUID), cria o diretório pai e apaga um arquivo pré-existente, monta o `TimelineExportAsset` (asset + `videoComposition` + `audioMix`) e entrega para `runExportSession`. Lá um `AVAssetExportSession` com preset `HighestQuality` grava `.mp4` com `shouldOptimizeForNetworkUse`, enquanto um `Timer` de 0,1 s publica `exporter.progress`. Com `preserveSourceQuality`, a `videoComposition` usa o frame rate nominal do primeiro vídeo, limitado a 1–240 fps; a opção MediaCodec é específica do Android e o iOS mantém seu pipeline nativo de cor. Ao final, o handler volta para a main queue, invalida o timer, chama o `onDispose` (que limpa a composição temporária no caso de `exportTimeline`) e responde com o path ou com `export_failed`.

No Android o caminho é `TimelineCompositionExporter`. Ele prepara o arquivo de saída (`cacheDir` com UUID quando não informado), monta a `Composition` com os mesmos builders do preview e aplica o `hdrMode` recebido. Com `preserveSourceQuality`, lê o bitrate de cada fonte e configura um `DefaultEncoderFactory` com o maior valor encontrado e fallback habilitado. Depois cria um `Transformer` com listener de `onCompleted`/`onError` e chama `start(composition, path)`. Um `Runnable` de 100 ms consulta `getProgress(ProgressHolder)` e publica progresso normalizado (0–100 → 0.0–1.0). O plugin guarda o exporter em `activeExporters` para poder cancelá-lo em `onDetachedFromEngine`; `complete {}` garante que sucesso e erro sejam entregues uma única vez.

O plugin devolve apenas um path local. Levar o arquivo para a galeria é responsabilidade do app: no exemplo, `EditorController.export` chama `Gal.putVideo` e depois apaga o temporário.

## Passo a Passo

1. **Gatilho na UI** — `example/lib/editor/widgets/editor_top_bar.dart` → `_ExportButton` → `EditorController.export`
   Botão desabilitado durante `loading`, `exporting` ou sem timeline; o label mostra o percentual do `StreamBuilder<TimelineExportProgress>`.
2. **Preparação do destino (app)** — `example/lib/editor/editor_controller.dart` → `export`
   Cria `systemTemp/video_ultra_player_example_exports` e um nome com timestamp.
3. **Chamada Dart** — `lib/src/native_timeline_player.dart` → `exportCurrentTimeline(outputPath:)` (ou `exportTimeline(clips, …)`)
   Verifica `_exporting`, zera o cache do stream de progresso e chama a plataforma; o `finally` libera o mutex.
4. **Assinatura do progresso** — `NativeTimelinePlayer.exportProgress` → `MethodChannelVideoUltraPlayer.exportProgress`
   `exportEventChannel.receiveBroadcastStream()` (sem argumentos) → `TimelineExportProgress.fromMap`.
5. **Serialização** — `lib/video_ultra_player_method_channel.dart`
   `exportCurrentTimeline` envia `{textureId, outputPath}`; `exportTimeline` envia `{clips, outputPath, config}`. Ambos lançam `StateError` se o nativo devolver `null`.
6. **iOS — resolução do destino** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `exportOutputURL` + `prepareOutputDirectory`
   Cria diretórios intermediários e remove arquivo existente.
7. **iOS — montagem do asset** — `controller.buildCurrentExportAsset()` → `TimelineComposition.buildCurrentExportAsset(config:)` → `buildExportAsset`
    Reconstrói a composição a partir da lista corrente e devolve `TimelineExportAsset(asset, videoComposition, audioMix)`; `makeVideoComposition()` embute o `animationTool` dos textos na videoComposition exportada.
8. **iOS — sessão de export** — `runExportSession`
   `AVAssetExportSession(preset: HighestQuality)`, `outputFileType = .mp4`; a `videoComposition` mantém o frame rate nominal quando `preserveSourceQuality == true` e não aplica a política MediaCodec exclusiva do Android. Um `Timer` de 0,1 s emite `state: "exporting"`, e o resultado é tratado na main queue.
9. **Android — resolução do destino** — `.../TimelineCompositionController.kt` → `TimelineCompositionExporter.exportOutputFile`
   `File(outputPath)` ou `cacheDir/video_ultra_player_export_<uuid>.mp4`; cria diretório pai e apaga arquivo existente.
10. **Android — montagem da composição** — `startExportCurrentTimeline` → `exportFromClips` → `buildTimelineComposition(clips, renderSize, audioTrack, textOverlays, config)`
     Os mesmos builders usados no preview, incluindo a lista corrente de overlays (re-ancorada por clipe via `textOverlaysForClip`) e o modo HDR da `Composition`.
11. **Android — Transformer** — `Transformer.Builder(context).addListener{...}.build()` → `start(composition, path)`
    Quando a qualidade da fonte deve ser preservada, o builder recebe um `DefaultEncoderFactory` com o maior bitrate detectado e fallback habilitado. `progressRunnable` de 100 ms com `ProgressHolder`; `complete {}` entrega o resultado uma vez só.
12. **Publicação do progresso** — `TimelineExportProgressStreamHandler.emit` (iOS) / `ExportProgressStreamHandler.emit` (Android)
    Ambos clampam o progresso e emitem `{progress, state}`; `onListen` já emite `{0.0, "idle"}`.
13. **Retorno ao Dart** — `result(outputURL.path)` / `callback.onCompleted(outputFile.absolutePath)`
    A future de `exportCurrentTimeline` completa com o path.
14. **Pós-processamento (app)** — `EditorController._saveToGallery`
    `Gal.requestAccess` → `Gal.putVideo(path)` → apaga o temporário e define `exportMessage = 'Salvo na galeria'`.

### Caminhos alternativos

- **Export concorrente:** `StateError('Only one timeline export can run at a time.')` em Dart.
- **`exportProgress` sem export ativo:** `StateError('An export must be in progress before accessing exportProgress.')`.
- **`exportCurrentTimeline` sem `load`:** `_requireTextureId()` lança `StateError`.
- **`exportTimeline` com lista vazia:** `ArgumentError`.
- **`textureId` inexistente (Android):** `not_found` antes de criar o exporter.
- **Falha ao criar a sessão (iOS):** `export_failed` + `state: "failed"`; o `onDispose` roda para limpar a composição temporária.
- **Export falho ou cancelado (iOS):** `status == .failed/.cancelled` → `export_failed` com `exporter.error?.localizedDescription`; qualquer outro status inesperado também vira `export_failed`.
- **Falha no Transformer (Android):** `onError` apaga o arquivo de saída, emite `state: "failed"` e devolve `export_failed`.
- **Engine desanexada durante o export (Android):** `onDetachedFromEngine` chama `cancel()` em todos os `activeExporters`; um exporter cancelado não reporta mais nada.
- **Permissão de galeria negada (app):** `_saveToGallery` lança `Exception('Permissão da galeria negada')`, capturado por `export` e exibido na status bar.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/src/native_timeline_player.dart` | Mutex `_exporting`, cache do stream, validações |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | `exportTimeline`, `exportCurrentTimeline`, `exportProgress` |
| Serialização | `lib/video_ultra_player_method_channel.dart` | Payloads e `exportEventChannel` |
| Configuração | `lib/src/models/timeline_composition_config.dart` | Proporção, resolução, política HDR e preservação de qualidade |
| Modelo | `lib/src/models/timeline_export_progress.dart` | `TimelineExportState` e clamp do progresso |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | `exportTimeline`, `exportCurrentTimeline`, `runExportSession`, `TimelineExportProgressStreamHandler` |
| Nativo iOS | `ios/Classes/TimelineComposition.swift` | `buildExportAsset`, `buildCurrentExportAsset` |
| Nativo Android | `.../VideoUltraPlayerPlugin.kt` | `exportTimeline`, `exportCurrentTimeline`, `activeExporters`, `ExportProgressStreamHandler` |
| Nativo Android | `.../TimelineCompositionController.kt` | `TimelineCompositionExporter`, `startExportCurrentTimeline` |
| Consumidor | `example/lib/editor/editor_controller.dart` | Destino do arquivo, salvamento na galeria, estado de `exporting` |
| Consumidor | `example/lib/editor/widgets/editor_top_bar.dart` | Botão com percentual e spinner |
| Testes | `test/native_timeline_player_test.dart` | Concorrência, `StateError` de progresso, delegação |
| Testes | `test/video_ultra_player_method_channel_test.dart` | Payload de export e decodificação dos eventos |
| Testes | `test/timeline_export_progress_test.dart` | `fromMap`, clamp e fallback de estado |
| Testes Android | `android/src/test/.../TimelineExportQualityTest.kt` | Parsing HDR e seleção do bitrate da fonte |

## Regras de Negócio Relevantes

- **Um export por instância de player** — `_exporting` em `native_timeline_player.dart`; nada impede dois `NativeTimelinePlayer` diferentes exportarem em paralelo.
- **`exportProgress` só durante export** — o getter lança `StateError` fora da janela ativa, e o stream é recriado a cada export (`_exportProgressStream = null`).
- **`exportTimeline` não precisa de `load`** — trabalha só com a lista recebida; no iOS cria uma `TimelineComposition` própria que é descartada no `onDispose`.
- **`exportCurrentTimeline` reflete a edição** — reconstrói a partir da lista corrente, inclui a trilha de áudio externa ativa e queima os text overlays do preview (iOS: `animationTool` na videoComposition; Android: overlays passados a `exportFromClips`).
- **`exportTimeline` ignora trilha externa e textos** — no Android, `TimelineCompositionExporter.export` passa `audioTrack = null` e `textOverlays = emptyList()`; no iOS a composição nova nasce sem trilha externa e sem overlays. Paridade com a trilha de áudio.
- **Canal de progresso é global** — sem `textureId`; com dois players exportando ao mesmo tempo os eventos se misturariam.
- **Progresso sempre clampado** — nos dois nativos na emissão e novamente em `TimelineExportProgress.fromMap`.
- **Estado inicial é `idle`** — `onListen` emite `{progress: 0.0, state: "idle"}` imediatamente nas duas plataformas.
- **Arquivo existente é sobrescrito** — iOS remove o arquivo antes de exportar; Android chama `delete()` antes do `start`.
- **Destino default é temporário** — `temporaryDirectory` (iOS) / `cacheDir` (Android), com UUID no nome; o app é responsável por persistir.
- **`original` preserva o canvas da origem** — a dimensão normalizada do primeiro vídeo, já considerando rotação, define o `renderSize`; a legenda é calculada como fração da altura desse canvas.
- **Qualidade da fonte é uma política de melhor fidelidade** — overlays exigem re-encode. `preserveSourceQuality` pede o bitrate máximo da origem no Android e seu frame rate nominal no iOS, mas o encoder pode aplicar fallback conforme a capacidade do dispositivo.
- **Tone mapping via MediaCodec evita o caminho OpenGL** — `toneMapToSdrUsingMediaCodec` é aplicado à `Composition` Android para não depender de `GL_EXT_YUV_target`; fontes SDR não precisam de conversão HDR.

## Dependências Externas

- **iOS:** `AVAssetExportSession` (preset `AVAssetExportPresetHighestQuality`), `FileManager`, `Timer`.
- **Android:** `androidx.media3.transformer.Transformer`, `DefaultEncoderFactory`, `VideoEncoderSettings`, `ProgressHolder`, `Handler`/`Looper`, `MediaMetadataRetriever`, `java.io.File`.
- **App de exemplo:** `gal ^2.3.1` (`Gal.requestAccess`, `Gal.putVideo`).

## Observações

- Não existe cancelamento de export exposto ao Dart: o `cancel()` do exporter Android só é usado internamente no detach, e no iOS não há caminho de cancelamento. `docs/plan/onda-1-quick-wins.md` trata essa lacuna.
- O progresso do iOS depende de `AVAssetExportSession.progress`, que costuma se mover em degraus; o do Android vem de `Transformer.getProgress`, que pode responder `PROGRESS_STATE_UNAVAILABLE` — nesse caso o exporter publica `0.0` e o percentual "trava" na UI enquanto o export corre.
- No exemplo, o arquivo temporário é apagado depois de entrar na galeria e `exportPath` volta a `null` — a UI passa a mostrar apenas "Salvo na galeria".
- `TimelineExportProgress.idle()` é o `initialData` do `StreamBuilder` do botão, então o percentual começa em 0% mesmo antes do primeiro evento.

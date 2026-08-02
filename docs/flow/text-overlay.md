---
generated_at: 2026-08-02
source_commit: 21182b1
source_state: dirty
verified_at: 2026-08-02
status: current
related_plans:
  - docs/plan/text-overlays/00-indice.md
---

# Flow: Text Overlays na Timeline

> **Resumo:** Textos (conteúdo, fonte, cor, tamanho, posição, rotação, opacidade e janela de tempo própria) são adicionados à timeline, renderizados queimados na composição nativa — idênticos no preview e no MP4 exportado — e editados pelo app de exemplo (adicionar, arrastar, estilizar, remover, undo/redo).

## Visão Geral

O gatilho é o botão "Texto" na toolbar do editor de exemplo: `EditorController.addTextOverlay` cria um `TimelineTextOverlay` default (texto "Texto", centro do frame, `fontSize` 8% da altura, janela de 3 s a partir da posição atual de playback), seleciona-o e chama `NativeTimelinePlayer.addTextOverlay`. A partir daí a chamada atravessa as quatro camadas federadas: a API pública serializa o modelo para o mapa do channel, o `MethodChannelVideoUltraPlayer` envia `{textureId, overlay}` e o plugin nativo resolve o controller da sessão e aplica a mutação.

A renderização vive no pipeline compartilhado por preview e export — essa é a regra inegociável "export = preview". No iOS, `TimelineComposition.makeVideoComposition()` anexa um `AVVideoCompositionCoreAnimationTool` com a árvore de `CATextLayer` (`TextOverlayLayers`) à própria `videoComposition`, que é usada tanto pelo `AVPlayer` do preview quanto pelo `AVAssetExportSession` do export. No Android, cada overlay vira um `TimelineTextOverlay` (media3 `TextOverlay`) dentro de um `OverlayEffect` por clipe em `effectsFor` — o mesmo `buildTimelineComposition` alimenta o `CompositionPlayer` do preview e o `Transformer` do export.

Mutações seguem o padrão de edição do plugin: snapshot no histórico → mutar a lista `textOverlays` → re-renderizar. iOS faz um rebuild cirúrgico (`applyUpdatedVideoComposition`: só re-gera a videoComposition e reatribui ao item corrente, com `requestFrame` se pausado); Android reconstrói a `Composition` inteira porque efeitos Media3 são imutáveis — por isso a UI commita apenas no fim do gesto. Undo/redo restauram textos porque `TimelineEditSnapshot` agora guarda `textOverlays`.

Um detalhe crítico do Android: timestamps de efeito no Media3 são relativos ao `EditedMediaItem`, não à timeline. Por isso a função pura `textOverlaysForClip` filtra os overlays que intersectam a janela de cada clipe e re-ancora `startMs`/`endMs` subtraindo o `clipStartMs` do clipe; overlay fora de qualquer clipe simplesmente não vira efeito.

## Passo a Passo

1. **[UI/Controller]** — `example/lib/editor/widgets/editor_toolbar.dart` → `IconButton` "Texto" → `EditorController.addTextOverlay`
   Cria o overlay default na posição de playback, chama `player.addTextOverlay`, adiciona à lista local `_textOverlays`, seleciona (`_selectedTextOverlayId`) e notifica; em seguida abre `showTextEditSheet`.
2. **[API pública]** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.addTextOverlay`
   `_requireTextureId()` (lança `StateError` sem `load`) e delega com `overlay.toJson()`.
3. **[Contrato]** — `lib/video_ultra_player_platform_interface.dart` → `VideoUltraPlayerPlatform.addTextOverlay`
   Assinatura com `textureId` + mapa; default lança `UnimplementedError`.
4. **[Channel]** — `lib/video_ultra_player_method_channel.dart` → `MethodChannelVideoUltraPlayer.addTextOverlay`
   `invokeMethod('addTextOverlay', {textureId, overlay})`; `updateTextOverlay` e `removeTextOverlay` enviam `{textureId, overlayId}`.
5. **[Roteamento iOS]** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `handle(_:result:)` → `TimelinePlayerController.addTextOverlay`
   Parseia `TextOverlayDescriptor(dictionary:)` (falha → `FlutterError("invalid_arguments")`); no controller: `pushEditSnapshot()` → `composition.addTextOverlay` → `applyUpdatedVideoComposition()`.
6. **[Roteamento Android]** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `onMethodCall` → `TimelineCompositionController.addTextOverlay`
   Extrai `args["overlay"]` (ausente → `invalid_arguments`); no controller: `pushEditSnapshot()` → `textOverlays += TextOverlayDescriptor.from(...)` → `rebuildCompositionPreservingPlayback()`.
7. **[Renderização iOS]** — `ios/Classes/TextOverlayLayers.swift` → `makeTextOverlayParentLayer`
   Raiz `isGeometryFlipped = true`; cada overlay vira um `CATextLayer` com `NSAttributedString` (fonte resolvida por `resolveFont`: `fontPath` → PostScript name via Core Text, senão `fontFamily`, fallback `systemFont`), frame medido por `boundingRect` e centrado em `(x * width, y * height)`, `backgroundColor` só com alpha > 0, `opacity`, rotação via `transform.rotation.z`, janela `[start, end)` por `beginTime`/`duration` sobre `AVCoreAnimationBeginTimeAtZero`.
8. **[Renderização Android]** — `android/src/main/kotlin/com/andre/video_ultra_player/TextOverlay.kt` → `TimelineTextOverlay`
   `getText` devolve `SpannableString("")` fora da janela e, dentro, os spans (cor, fundo condicional, `AbsoluteSizeSpan` = `fontSize × renderHeight`, `AlignmentSpan`, `Typeface` custom cacheado por path); `getOverlaySettings` converte `(x, y)` 0..1 top-left → NDC com `StaticOverlaySettings.Builder` (âncoras, rotação, `alphaScale = opacity`).
9. **[Re-anchoragem Android]** — `TextOverlay.kt` → `textOverlaysForClip`
   `buildTimelineComposition` acumula `clipStartMs` por segmento e chama a função pura: intersecta `[clipStart, clipStart + clipDuration)` e subtrai `clipStartMs` da janela; o `OverlayEffect` entra em `effectsFor` depois do `Presentation`.
10. **[Export]** — iOS: `animationTool` embutido na `videoComposition` de `buildCurrentExportAsset`; Android: `startExportCurrentTimeline` passa `textOverlays` a `exportFromClips`. `exportTimeline(clips)` standalone exporta sem textos (paridade com a trilha de áudio).
11. **[UI — edição contínua]** — `example/lib/editor/widgets/preview_area.dart` (ghost arrastável) + `text_edit_sheet.dart` + `text_track_row.dart`
    O ghost segue o dedo via `updateSelectedTextOverlayPosition` (só cópia local); no release `commitSelectedTextOverlayPosition` → `commitTextOverlay` → `player.updateTextOverlay` (commit-only). O sheet e os blocos da faixa editam/selecionam via `selectTextOverlay`/`commitTextOverlay`/`removeSelectedTextOverlay`.
12. **[Undo/redo]** — nativo `undo()`/`redo()` → `restoreEditSnapshot` restaura `textOverlays`; no exemplo, `_EditorSnapshot` guarda a lista local e a seleção.

### Caminhos alternativos

- **Sem `load`:** `_requireTextureId()` lança `StateError` em Dart.
- **Overlay com `id` inexistente em update/remove:** no-op nas duas plataformas (iOS re-renderiza a mesma composição; Android só re-emite estado) — e no Dart `commitTextOverlay` do exemplo também retorna se o id não está na lista local.
- **`fontPath` inválido ou ausente:** fallback para `fontFamily` e depois fonte do sistema — nunca falha o load nem o render.
- **Overlay fora de qualquer clipe:** no Android `textOverlaysForClip` descarta; no iOS `makeTextLayer` retorna `nil` quando a janela não cabe na duração total.
- **Janela `end <= start`:** clampada defensivamente pelo `commitTextOverlay` do exemplo (`start + 1 s`); o `RangeSlider` do sheet também garante ordem.
- **Erro nativo:** iOS responde `invalid_arguments` (parse) ou `edit_failed`; Android `invalid_arguments`/`edit_failed` com stack trace via `Log.getStackTraceString`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Modelo | `lib/src/models/timeline_text_overlay.dart` | `TimelineTextOverlay` + `TimelineTextAlign`, `toJson` em ms, asserts |
| API pública | `lib/src/native_timeline_player.dart` | `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` com `_requireTextureId()` |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | 3 assinaturas federadas |
| Channel | `lib/video_ultra_player_method_channel.dart` | Payloads `{textureId, overlay}` / `{textureId, overlayId}` |
| Nativo iOS | `ios/Classes/TimelineComposition.swift` | `TextOverlayDescriptor`, estado `textOverlays`, `animationTool` em `makeVideoComposition`, snapshot |
| Nativo iOS | `ios/Classes/TextOverlayLayers.swift` | Árvore CALayer/CATextLayer, `resolveFont`, janela de tempo |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | 3 cases + `TimelinePlayerController.applyUpdatedVideoComposition` |
| Nativo iOS | `ios/Classes/TimelineEditModel.swift` | Snapshot com `textOverlays` |
| Nativo Android | `android/src/main/kotlin/com/andre/video_ultra_player/TextOverlay.kt` | `TextOverlayDescriptor`, `textOverlaysForClip`, `TimelineTextOverlay` |
| Nativo Android | `.../TimelineCompositionController.kt` | Estado, mutações, `buildTimelineComposition`/`effectsFor`/`editedMediaItemFor` com overlays, export |
| Nativo Android | `.../VideoUltraPlayerPlugin.kt` | 3 cases no `when` |
| Nativo Android | `.../TimelineEditModel.kt` | Snapshot com `textOverlays` |
| Consumidor | `example/lib/editor/editor_controller.dart` | Lista local, seleção, `commitTextOverlay` (porta única de mutação), snapshots locais |
| Consumidor | `example/lib/editor/widgets/text_edit_sheet.dart` | Sheet de estilo/janela/exclusão (commit-only) |
| Consumidor | `example/lib/editor/widgets/text_track_row.dart` | Faixa de textos na timeline |
| Consumidor | `example/lib/editor/widgets/preview_area.dart` | Ghost arrastável sobre a `Texture` |
| Testes | `test/timeline_text_overlay_test.dart` | Serialização, asserts, `copyWith`, igualdade |
| Testes | `test/native_timeline_player_test.dart` | Delegação + `StateError` sem load |
| Testes | `test/video_ultra_player_method_channel_test.dart` | Payloads exatos |
| Testes | `android/src/test/kotlin/com/andre/video_ultra_player/TextOverlayDescriptorTest.kt` | Parsing, clamps, `textOverlaysForClip`, snapshot |
| Testes | `example/test/text_edit_sheet_test.dart`, `text_track_row_test.dart` | Widget tests com `FakeTimelinePlayer` |

## Regras de Negócio Relevantes

- **"Export = preview"** — textos vivem na `videoComposition` (iOS) e nos efeitos de `buildTimelineComposition` (Android), os dois pipelines compartilhados por preview e export; `exportTimeline(clips)` standalone não tem overlays.
- **Janela `[start, end)`** — `end` é clampado pela duração total; fora da janela o overlay não renderiza (string vazia no Android, layer inexistente no iOS).
- **`fontPath` vence `fontFamily`** — `resolveFont` (iOS) e `typefaceFor` (Android), com fallback que nunca falha.
- **Timestamps Media3 são relativos ao item** — `textOverlaysForClip` re-ancora a janela por clipe; função pura testável.
- **Mutações commit-only** — Android reconstrói a `Composition` (efeitos imutáveis); o app chama `commitTextOverlay` apenas no commit do gesto.
- **Âncora = centro do texto** — `(x, y)` 0..1 top-left em ambas as plataformas; divergência de métrica de fonte entre plataformas é aceita (paridade aproximada).

## Dependências Externas

- **iOS:** `AVVideoCompositionCoreAnimationTool`, `AVCoreAnimationBeginTimeAtZero`, `CoreText` (`CTFontManagerRegisterFontsForURL`, `CTFontManagerCreateFontDescriptorsFromURL`).
- **Android:** `androidx.media3:media3-effect` 1.10.1 (`TextOverlay`, `OverlayEffect`, `StaticOverlaySettings`), `com.google.common` (não usado — ver Observações), `android.graphics.Typeface`.
- **App de exemplo:** nenhuma nova — consome a API do plugin.

## Observações

- **Drift de API no media3 1.10.1:** `TextOverlay` estende `BitmapOverlay` e não declara `getOverlaySettings` — o posicionamento vem do override herdado de `TextureOverlay.getOverlaySettings` retornando `StaticOverlaySettings.Builder`; `OverlayEffect` recebe `List<TextureOverlay>` (a lista Kotlin direta, pois `ImmutableList` Java quebra a inferência de overload).
- **`end > start` não é assertado no construtor Dart** — comparação de `Duration` não é const-evaluable; a exigência é documentada e tratada pelo nativo e pelo app.
- **Quirk conhecido do CoreAnimationTool:** se o texto aparecer fora da janela no teste manual, o fallback documentado em `TextOverlayLayers.makeTextLayer` é keyframe de `opacity` ancorado em `AVCoreAnimationBeginTimeAtZero`.
- **Fix pré-existente no caminho:** `VideoUltraPlayerPlugin.mainHandler` (Android) virou `lazy` para o teste JVM existente compilar sem `Looper` mockado — comportamento de runtime preservado.
- **Paridade visual aproximada** — métricas de fonte e baseline divergem entre iOS e Android; o teste manual deve validar posição/tamanho com a âncora no centro.

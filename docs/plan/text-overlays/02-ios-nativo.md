# Text Overlays na Timeline — Parte 2: iOS Nativo

> **Objetivo da parte:** Textos renderizados via `AVVideoCompositionCoreAnimationTool` na `videoComposition` iOS — visíveis no preview (Texture) e queimados no MP4 exportado — com mutações add/update/remove integradas ao undo/redo.
> **Plano:** `00-indice.md` (Design de Origem, contrato do modelo, ordem e dependências)
> **Depende de:** parte 1 concluída (contrato de chaves do channel)

## Contexto

No iOS, `TimelineComposition.makeVideoComposition()` (linha ~487 de `ios/Classes/TimelineComposition.swift`) já é o ponto único por onde passam preview (`build` → `playerItem.videoComposition`) e export (`buildCurrentExportAsset` → `exporter.videoComposition`, linha ~391 do plugin). Anexar o `animationTool` ali cobre os dois caminhos automaticamente. Para mutações, o precedente é `setClipAlignment` (plugin linha ~607): `pushEditSnapshot()` → mutar → re-gerar **só** a `videoComposition` e reatribuir a `player.currentItem?.videoComposition` — sem remontar a `AVMutableComposition`, o que é barato e preserva playback. Undo/redo usam `rebuildPreservingPlayback` (rebuild completo), que também passa por `makeVideoComposition()` — um único caminho de renderização cobre tudo.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `ios/Classes/TimelineComposition.swift` | editar | `TextOverlayDescriptor`, estado `textOverlays`, mutações, `animationTool` em `makeVideoComposition()`, snapshot |
| `ios/Classes/TextOverlayLayers.swift` | criar | Construção da árvore CALayer/CATextLayer + registro/resolução de fontes (sistema e `fontPath`) |
| `ios/Classes/TimelineEditModel.swift` | editar | `TimelineEditSnapshot` ganha `textOverlays` |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | 3 cases no routing + métodos no `TimelinePlayerController` |

## Fases

### Fase 1 — Descriptor, estado e snapshot

- [ ] Em `ios/Classes/TimelineComposition.swift`, adicionar `struct TextOverlayDescriptor` (junto a `AudioTrackDescriptor`, linha ~101) com `init?(dictionary:)` failable: `id` e `text` obrigatórios (guard), `startMs`/`endMs` (Int64), `x`/`y` (CGFloat, clamp 0...1), `rotationDegrees` (default 0), `fontSize` (clamp 0.01...1), `color`/`backgroundColor` (UInt32 ARGB via NSNumber), `fontFamily`/`fontPath` (String?), `opacity` (clamp 0...1, default 1), `textAlign` (String, default "center")
- [ ] Adicionar à classe `TimelineComposition`: `private(set) var textOverlays: [TextOverlayDescriptor] = []` e os métodos sem rebuild (caller é responsável, mesmo padrão de `setAudioTrack`):
  - `addTextOverlay(_ descriptor:)` — append
  - `updateTextOverlay(_ descriptor:)` — substitui o elemento com mesmo `id` (no-op se não existir)
  - `removeTextOverlay(id:)` — remove por `id` (no-op se não existir)
- [ ] Em `makeEditSnapshot()`/`restoreEditSnapshot(_:)`, incluir `textOverlays`
- [ ] Em `ios/Classes/TimelineEditModel.swift`, adicionar `let textOverlays: [TextOverlayDescriptor]` a `TimelineEditSnapshot` e atualizar o init memberwise
- [ ] Verificação: `cd example && flutter build ios --no-codesign` compila (build apenas — não executar o app). Se o ambiente não tiver CocoaPods configurado, registrar o bloqueio e seguir — a verificação mínima é ausência de erros de sintaxe nos arquivos alterados

### Fase 2 — Renderização (CALayer/CATextLayer)

- [ ] Criar `ios/Classes/TextOverlayLayers.swift` com:
  - `func makeTextOverlayParentLayer(overlays:renderSize:totalDuration:) -> CALayer` — raiz com `frame = CGRect(origin: .zero, size: renderSize)` e `isGeometryFlipped = true` (origem top-left, casando com x/y normalizados)
  - Uma `CATextLayer` por overlay: `string` = `NSAttributedString` com fonte, cor e alinhamento (`NSMutableParagraphStyle`); `frame` dimensionado ao texto (`NSAttributedString.boundingRect`) e centrado em `(x * width, y * height)`; `backgroundColor` aplicado só quando o alpha de `backgroundColor` > 0; `opacity` do overlay; rotação via `setValue(rotationDegrees * .pi / 180, forKeyPath: "transform.rotation.z")`; `isWrapped = true`
  - Janela de tempo: `beginTime = AVCoreAnimationBeginTimeAtZero + startSeconds`, `duration = endSeconds - startSeconds` (end clampado por `totalDuration`), `fillMode = .forwards`, `isRemovedOnCompletion = false`. Se o texto aparecer fora da janela no teste manual, adicionar keyframe de `opacity` (0→1 no start, 1→0 no end) sobre `AVCoreAnimationBeginTimeAtZero` — anotar esse fallback como comentário no código
  - `func resolveFont(fontFamily:fontPath:size:) -> UIFont` — se `fontPath` existir no disco: registrar via `CTFontManagerRegisterFontsForURL` (ignorar erro de "já registrado") e usar o PostScript name via `CTFontCopyPostScriptName`; senão `UIFont(name: fontFamily)`; fallback `UIFont.systemFont(ofSize:)`. `fontSize` em pontos = fração × `renderSize.height`
- [ ] Em `TimelineComposition.makeVideoComposition()`, ao final: se `!textOverlays.isEmpty`, montar `videoLayer` (frame = renderSize) + `outputLayer` (frame = renderSize, contém `videoLayer` e a parent layer de texto) e atribuir `videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: outputLayer)`
- [ ] Verificação: `flutter build ios --no-codesign` compila

### Fase 3 — Mutações no controller + routing

- [ ] Em `ios/Classes/VideoUltraPlayerPlugin.swift`, adicionar ao `TimelinePlayerController` (após `removeAudioTrack`, linha ~690), seguindo o padrão de `setClipAlignment` (snapshot → mutate → re-gerar videoComposition → reatribuir):
  ```swift
  func addTextOverlay(_ descriptor: TextOverlayDescriptor) {
    pushEditSnapshot()
    composition.addTextOverlay(descriptor)
    applyUpdatedVideoComposition()
  }
  ```
  e equivalentes `updateTextOverlay`/`removeTextOverlay(id:)`
- [ ] Adicionar `private func applyUpdatedVideoComposition()`: re-gerar via um novo método internal `composition.updatedVideoComposition()` (wrapper de `makeVideoComposition()`), atribuir a `player.currentItem?.videoComposition`, e — se `player.rate == 0` — fazer seek de tolerância zero na posição atual + `texture.requestFrame()` para o frame pausado refletir o texto imediatamente; `emitState()` ao final
- [ ] Adicionar os 3 cases no `handle(_:result:)` (após `removeAudioTrack`, linha ~214):
  - `"addTextOverlay"`/`"updateTextOverlay"`: guard `controller` + `args["overlay"] as? [String: Any]` + `TextOverlayDescriptor(dictionary:)`; falha de parse → `result(FlutterError(code: "invalid_arguments", ...))` (melhor que o guard silencioso do `setAudioTrack`); sucesso → `result(nil)`
  - `"removeTextOverlay"`: guard `controller` + `args["overlayId"] as? String`; sucesso → `result(nil)`
- [ ] Verificação: `flutter build ios --no-codesign` compila; revisar que `exportCurrentTimeline` não precisa de alteração (o `animationTool` já vai na `videoComposition` exportada — confirmar lendo `runExportSession`, linha ~364)
- [ ] Checkpoint: commit das mudanças da parte + informar o usuário que a parte 2 está concluída e a parte 3 está pronta para execução

## Critérios de Sucesso

- [ ] Plugin iOS compila sem erros (`flutter build ios --no-codesign`)
- [ ] `makeVideoComposition()` é o único ponto de criação de videoComposition e inclui o `animationTool` quando há textos
- [ ] Undo/redo restauram textos (snapshot inclui `textOverlays` e o rebuild passa pelo mesmo `makeVideoComposition()`)
- [ ] `exportTimeline(clips)` (sem player) segue exportando sem textos — paridade com a trilha de áudio
- [ ] _(manual — feito pelo usuário)_ Texto aparece no preview na janela correta, some fora dela, e sai queimado no MP4 exportado

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Texto visível fora da janela (quirk do CoreAnimationTool com `beginTime`) | Média | Fallback documentado: keyframe de opacity ancorado em `AVCoreAnimationBeginTimeAtZero` |
| `CATextLayer` não renderiza emoji/alguns glifos | Baixa | Aceitar limitação do v1; `CATextLayer` usa Core Text |
| Fonte custom falha ao registrar (path inválido) | Baixa | Fallback para system font; nunca propagar erro |
| `isGeometryFlipped` inconsistente entre preview e export | Média | O `animationTool` é aplicado pela mesma videoComposition nos dois caminhos; validar orientação (y=0 no topo) no teste manual |

## Rollback

`git revert` do commit do checkpoint da parte. Tudo é aditivo: sem overlays na lista, `makeVideoComposition()` se comporta exatamente como antes (sem `animationTool`).

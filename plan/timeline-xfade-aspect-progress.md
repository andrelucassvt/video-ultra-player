# Timeline: Transições Xfade, Aspect Ratio de Output e Progresso Real de Export

> **Objetivo:** Entregar três capacidades federadas no Native Timeline Player — (1) crossfade (xfade) uniforme entre clipes, (2) controle do aspect ratio do output por preset, e (3) progresso real de exportação — válidas **tanto no preview ao vivo (`Texture`) quanto no MP4 exportado**, com paridade iOS/Android.

## Contexto

O Native Timeline Player hoje monta uma composição **gapless sequencial** (clipes encostados, sem overlap), com `renderSize` derivado do primeiro clipe e `exportTimeline` retornando só o path final, sem feedback de progresso. As três features pedidas mudam o contrato Dart↔nativo: transição e aspect ratio são configuração **de composição** (não por clipe) e precisam alimentar `load()` _e_ `exportTimeline()`, já que o usuário pediu paridade preview+export. O progresso exige um canal de eventos dedicado.

Decisões já tomadas com o usuário:

- **Escopo:** Export **+** Preview (paridade).
- **Transição:** global uniforme — um único `transitionDuration` aplicado entre todos os clipes.
- **Aspect ratio:** preset enum (`ratio16x9`, `ratio9x16`, `ratio1x1`, `original`) + resolução base.

## Premissas técnicas confirmadas

- **iOS (settled):** crossfade clássico AVFoundation — duas video tracks alternadas na `AVMutableComposition`, overlap de `transitionDuration`, `setOpacityRamp(...)` nas layer instructions (+ `setVolumeRamp` para áudio). A **mesma** `AVVideoComposition` alimenta `AVPlayer` (preview) e `AVAssetExportSession` (export), então a paridade é praticamente de graça. Aspect ratio = `renderSize` derivado do preset. Progresso = polling de `AVAssetExportSession.progress`.
- **Android (investigação obrigatória):** Media3 1.10.1 **não** tem crossfade nativo — `EditedMediaItemSequence` é explicitamente **não-sobreposto** (clipes empilhados em sequência, sem overlap). Crossfade exige **múltiplas sequências compositadas** com alpha variável no tempo, e efeitos estáticos (`Crop`, alpha constante) **não fazem ramp** → provável necessidade de um `GlShaderProgram`/overlay animado custom. Aspect ratio = `Presentation` (efeito de composição) — esse sim suportado em preview e export. ([refs nas Fontes](#fontes))

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models/timeline_composition_config.dart` | criar | Modelo `TimelineCompositionConfig` (transitionDuration, `OutputAspectRatio`, resolução base) + enum `OutputAspectRatio`; `toJson()`. |
| `lib/src/models/timeline_export_progress.dart` | criar | Modelo `TimelineExportProgress` (`progress` 0..1, `state`) + `fromMap`. |
| `lib/video_ultra_player.dart` | editar | Exportar os novos tipos. |
| `lib/src/native_timeline_player.dart` | editar | `load()` e `exportTimeline()` passam a aceitar `TimelineCompositionConfig`; novo getter `exportProgress` (Stream). |
| `lib/video_ultra_player_platform_interface.dart` | editar | Novas assinaturas com config + `Stream<TimelineExportProgress> exportProgress()`. |
| `lib/video_ultra_player_method_channel.dart` | editar | Serializar config nos payloads `load`/`exportTimeline`; novo `EventChannel('video_ultra_player/timeline_player/export')` mapeado para `TimelineExportProgress`. |
| `ios/Classes/TimelineComposition.swift` | editar | Build com 2 tracks alternadas + opacity/volume ramps; `renderSize` por preset; recálculo de duração com overlap. |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | Parse da config em `load`/`exportTimeline`; timer de `progress` do `AVAssetExportSession` emitindo no novo EventChannel. |
| `android/.../TimelineCompositionController.kt` | editar | `Presentation` por preset; crossfade via investigação (multi-sequence + alpha ramp custom); recálculo de duração com overlap; `Transformer.getProgress` polling. |
| `android/.../VideoUltraPlayerPlugin.kt` | editar | Parse da config; registrar EventChannel de progresso; encaminhar progresso do exporter. |
| `example/lib/main.dart` | editar | Controles de aspect ratio, slider de transição, barra de progresso de export. |
| `test/*` | editar/criar | Contratos Dart (serialização da config, payloads de channel, mapping do progress stream). |
| `flow/native-timeline-player.md` | editar | Atualizar fluxo com config de composição, overlap e canal de progresso. |

### Contrato (formato dos novos campos)

```jsonc
// config enviada em load e exportTimeline
"config": {
  "transitionDurationMs": 500,           // 0 = sem transição (hard cut)
  "aspectRatio": "ratio9x16",            // ratio16x9 | ratio9x16 | ratio1x1 | original
  "baseWidth": 1080                       // lado maior; o outro lado deriva do ratio
}
// evento do EventChannel de progresso
{ "progress": 0.42, "state": "exporting" } // state: idle|exporting|completed|failed
```

## Fases

> Mudança **Logic** (serialização, contrato de channel, serviços nativos) → **TDD**: os contratos Dart vêm antes da implementação. A camada nativa Swift/Kotlin permanece com testes leves (só os já existentes de `notImplemented`).

### Fase 1 — Contrato Dart e modelos (testes primeiro)

> Escreva os testes que definem serialização e validação. Eles falham até a Fase 2.

- [ ] Criar `test/timeline_composition_config_test.dart`: `toJson()` emite `transitionDurationMs`, `aspectRatio` (string do enum) e `baseWidth`; default = `original`, `transitionDurationMs: 0`.
- [ ] Testar validação: `transitionDuration` negativo lança `ArgumentError`; `baseWidth <= 0` lança `ArgumentError`.
- [ ] Criar `test/timeline_export_progress_test.dart`: `fromMap` converte `{progress, state}` em `TimelineExportProgress` com `progress` clampado em `0..1` e `state` mapeado para enum.
- [ ] Estender `test/native_timeline_player_test.dart`: `load(clips, config:)` e `exportTimeline(clips, config:)` repassam a config serializada ao fake platform; `exportProgress` exige export em andamento.
- [ ] Verificação: `flutter test` compila e falha só por API inexistente (não por sintaxe).

### Fase 2 — Implementação do contrato Dart (fazer os testes passarem)

- [ ] Criar `lib/src/models/timeline_composition_config.dart` com enum `OutputAspectRatio { ratio16x9, ratio9x16, ratio1x1, original }`, classe imutável `TimelineCompositionConfig({Duration transitionDuration = Duration.zero, OutputAspectRatio aspectRatio = OutputAspectRatio.original, int baseWidth = 1080})`, asserts e `toJson()`.
- [ ] Criar `lib/src/models/timeline_export_progress.dart` com enum `TimelineExportState` e `fromMap`.
- [ ] Editar `lib/video_ultra_player_platform_interface.dart`: `load(clips, {config})`, `exportTimeline(clips, {outputPath, config})`, `Stream<TimelineExportProgress> exportProgress()`.
- [ ] Editar `lib/video_ultra_player_method_channel.dart`: incluir `config.toJson()` nos payloads; registrar `EventChannel('video_ultra_player/timeline_player/export')` e mapear para `TimelineExportProgress`.
- [ ] Editar `lib/src/native_timeline_player.dart`: novos parâmetros `config` (default `const TimelineCompositionConfig()`) em `load`/`exportTimeline`; getter `exportProgress`.
- [ ] Editar `lib/video_ultra_player.dart` para exportar os novos tipos.
- [ ] Verificação: `flutter test` e `flutter analyze` passam.

### Fase 3 — iOS nativo (preview + export, settled)

- [ ] Parse da `config` em `ios/Classes/VideoUltraPlayerPlugin.swift` (`load` e `exportTimeline`); converter preset → `renderSize` (lado maior = `baseWidth`; `original` = tamanho do primeiro clipe normalizado).
- [ ] Em `TimelineComposition.build`: criar **duas** `AVMutableCompositionTrack` de vídeo (A/B); inserir clipes alternando track; quando `transitionDuration > 0`, posicionar o clipe seguinte com overlap de `transitionDuration` sobre o anterior.
- [ ] Em `makeVideoComposition`: durante cada janela de overlap, instrução com **duas** layer instructions — `setOpacityRamp(fromStartOpacity: 1→0)` no clipe que sai e `0→1` no que entra; fora do overlap, instrução single-layer como hoje. Áudio: `setVolumeRamp` equivalente.
- [ ] **Recalcular duração com overlap** (item crítico): `totalDuration`, fronteiras de `TimelineSegment`, `playbackState(at:)` e `emitState` devem subtrair `Σ(overlaps)`; o scrubber e o `stateStream` desync se isso ficar na duração sequencial antiga.
- [ ] **Fill-mode parity:** manter o cover-crop atual ao forçar ratio ≠ source (decisão única: _scale-to-fill + crop_, espelhada no Android).
- [ ] Progresso: em `exportTimeline`, `Timer`/`DispatchSourceTimer` lê `exportSession.progress` (~10 Hz) e emite `{progress, state}` no EventChannel; emitir `completed`/`failed` no handler de conclusão.
- [ ] Verificação: `cd example && flutter run -d ios` — preview mostra crossfade + ratio escolhido; `Export MP4` reporta progresso e o MP4 reflete os dois.

### Fase 4 — Android nativo (investigação gated + implementação)

> Crossfade no `CompositionPlayer` é o único item não confirmado. Resolver a investigação **antes** de implementar o overlap.

- [ ] **Investigação (bloqueante):** validar no código/sample do Media3 1.10.1 se `CompositionPlayer` (preview) consegue compositar **múltiplas `EditedMediaItemSequence` sobrepostas no tempo** com alpha variável. Resultado decide a rota:
  - **Rota A** — multi-sequence + efeito de alpha-ramp custom (`GlShaderProgram`/`OverlayEffect` animado por timestamp) aplicado nas bordas; clipes ímpares na sequência 1, pares na sequência 2, com gaps que geram overlap de `transitionDuration`.
  - **Rota B (fallback explícito)** — se o preview não compositar com alpha ao vivo: **escalar a decisão de paridade ao usuário** (bump de versão Media3, shader custom, ou aceitar preview hard-cut). **Não** degradar silenciosamente para preview hard-cut + export com fade — isso quebra a paridade pedida.
- [ ] Aspect ratio: adicionar `Presentation.createForWidthAndHeight(w, h, LAYOUT_SCALE_TO_FIT_WITH_CROP)` como efeito de composição (vídeo), derivado do preset; aplicar em `buildTimelineComposition` para preview e export. Conferir que o `setVideoSurface`/`setDefaultBufferSize` usa as dimensões do preset, não `1280x720` fixo.
- [ ] Implementar overlap conforme a rota escolhida em `buildTimelineComposition`; aplicar volume fade no áudio das sequências sobrepostas.
- [ ] **Recalcular duração com overlap** (item crítico, espelha o iOS): `rebuildSegments`, `totalDurationMs`, `segmentIndexFor`, `seekTo` (clamp) e `emitState` (`clipIndex`/`localPosition`) devem usar a duração com overlap, não a soma sequencial.
- [ ] **Fill-mode parity:** usar `LAYOUT_SCALE_TO_FIT_WITH_CROP` para casar com o cover-crop do iOS.
- [ ] Progresso: em `TimelineCompositionExporter`, `Handler` periódico com `Transformer.getProgress(ProgressHolder)` (~10 Hz) emitindo `{progress, state}`; emitir `completed` em `onCompleted` e `failed` em `onError`. Registrar o `EventChannel` de progresso em `VideoUltraPlayerPlugin.kt`.
- [ ] Verificação: `cd example && flutter run -d android` — paridade visual com iOS (crossfade, ratio) e barra de progresso real.

### Fase 5 — App de exemplo (UI dos controles)

- [ ] Em `example/lib/main.dart`: seletor de `OutputAspectRatio` (segmented/dropdown), slider de `transitionDuration` (0–1500 ms), e barra de progresso ligada a `player.exportProgress`.
- [ ] Passar o `TimelineCompositionConfig` montado tanto em `_player.load(...)` quanto em `_exportTimeline(...)`; o `Texture` deve renderizar dentro de um `AspectRatio` que segue o preset.
- [ ] Verificação: trocar ratio/transição reflete no preview ao vivo; export mostra progresso indo de 0 a 100% e termina com o path.

### Fase 6 — Atualizar Flow

- [ ] Atualizar `flow/native-timeline-player.md`: documentar `TimelineCompositionConfig` (transição global + aspect preset) fluindo por `load` **e** `exportTimeline`, o overlap que encurta a duração total, o cover-crop como fill-mode comum, e o novo `EventChannel` de progresso de export.
- [ ] Verificação: o flow descreve os caminhos reais (arquivos/funções) das três features.

## Critérios de Sucesso

- [ ] Preview ao vivo e MP4 exportado mostram o **mesmo** crossfade e o **mesmo** aspect ratio (paridade Export+Preview).
- [ ] `exportProgress` emite valores monotônicos de ~0.0 a 1.0 e termina em `completed` (ou `failed`).
- [ ] Scrubber e `stateStream` permanecem corretos com transição ativa (duração total reflete os overlaps).
- [ ] Paridade visual iOS ↔ Android nos três comportamentos.
- [ ] Build sem erros; `flutter analyze` limpo.
- [ ] Todos os testes unitários Dart passando.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Crossfade ao vivo no `CompositionPlayer` (Android) não suportado em 1.10.1 | Alta | Fase 4 começa por investigação gated; fallback A (shader/overlay custom) e, se inviável, escalar ao usuário (Rota B) — sem degradar paridade em silêncio. |
| Duração total não recalculada com overlap → scrubber/`stateStream` desync | Alta | Item de checklist explícito nas Fases 3 e 4 cobrindo total, segmentos, seek clamp e emitState. |
| Clipe mais curto que 2×`transitionDuration` colide; 1º clipe sem in-transition, último sem out-transition | Média | Clampar `transitionDuration` por par ao mínimo entre metades das durações vizinhas; sem transição na borda inicial/final. |
| Fill-mode divergente entre iOS (cover-crop) e Android (`Presentation`) ao forçar ratio | Média | Fixar _scale-to-fill + crop_ nas duas plataformas (`LAYOUT_SCALE_TO_FIT_WITH_CROP`). |
| Progresso com múltiplos exports simultâneos | Baixa | Assumir **um export ativo por vez** (sem keying por exportId); documentar a premissa. |

## Rollback

Reverter o commit da feature. O contrato Dart é aditivo (config com defaults `Duration.zero`/`original` reproduz o comportamento gapless atual), então um rollback parcial pode manter os modelos e neutralizar a feature passando `const TimelineCompositionConfig()`.

## Fontes

- Media3 `EditedMediaItemSequence` é não-sobreposto (sem crossfade nativo): [issue androidx/media #1662](https://github.com/androidx/media/issues/1662), [Media3 1.10 release](https://android-developers.googleblog.com/2026/03/media3-110-is-out.html)
- Fade via OpenGL/GlShaderProgram no Media3 Transformer: [blog.sdex.dev — Video Fade Effect](https://blog.sdex.dev/Video-Fade-Effect/)

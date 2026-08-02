# Text Overlays na Timeline — Parte 3: Android Nativo

> **Objetivo da parte:** Textos renderizados via `OverlayEffect`/`TextOverlay` (media3-effect) nos efeitos por clipe — visíveis no preview (`CompositionPlayer`) e queimados no MP4 exportado (`Transformer`) — com mutações add/update/remove integradas ao undo/redo e testes Kotlin passando.
> **Plano:** `00-indice.md` (Design de Origem, contrato do modelo, ordem e dependências)
> **Depende de:** parte 1 concluída (contrato de chaves do channel)

## Contexto

No Android, `buildTimelineComposition(clips, renderSize, audioTrack)` (linha ~525 de `TimelineCompositionController.kt`) é o ponto único por onde passam preview (`setComposition`) e export (`TimelineCompositionExporter.exportFromClips`). Efeitos Media3 são imutáveis — toda mutação de texto exige `rebuildCompositionPreservingPlayback()` (commit-only, gotcha do projeto). O detalhe crítico: **timestamps de overlay são relativos ao `EditedMediaItem`**, não à timeline — por isso os overlays são filtrados e re-ancorados por clipe usando o `startMs` acumulado de cada segmento. A lógica de janela por clipe fica numa função pura (sem classes Android), testável em unit test JVM.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `android/src/main/kotlin/com/andre/video_ultra_player/TextOverlay.kt` | criar | `TextOverlayDescriptor`, `TimelineTextOverlay : TextOverlay` (media3), função pura `textOverlaysForClip` |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | editar | Estado `textOverlays`, mutações, parâmetro em `buildTimelineComposition`/`editedMediaItemFor`/`effectsFor`, snapshot, export |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt` | editar | `TimelineEditSnapshot` ganha `textOverlays` |
| `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | editar | 3 cases no routing |
| `android/src/test/kotlin/com/andre/video_ultra_player/TextOverlayDescriptorTest.kt` | criar | Testes de parsing e da janela por clipe |

## Fases

### Fase 1 — Testes Kotlin (contrato antes da implementação)

> Os testes vão falhar inicialmente (classes inexistentes) — isso é intencional.

- [x] Criar `android/src/test/kotlin/com/andre/video_ultra_player/TextOverlayDescriptorTest.kt` (JUnit via `kotlin.test`, padrão do `VideoUltraPlayerPluginTest.kt` existente):
  - `from(map)` parseia todos os campos do contrato (`id`, `text`, `startMs`, `endMs`, `x`, `y`, `rotationDegrees`, `fontSize`, `color`, `backgroundColor`, `opacity`, `textAlign`, opcionais `fontFamily`/`fontPath`)
  - `from` lança quando `id` ou `text` faltam; faz clamp de `x`/`y`/`fontSize`/`opacity`
  - `textOverlaysForClip(overlays, clipStartMs, clipEndMs)`: mantém overlay que intersecta `[clipStart, clipEnd)`, descarta os demais, e re-ancora a janela subtraindo `clipStartMs` (clamp em 0 e na duração do clipe)
  - `TimelineEditSnapshot` carrega e devolve `textOverlays` (round-trip por `copy`)
- [x] Verificação: `cd example/android && ./gradlew testDebugUnitTest` — os testes novos falham por classe inexistente (erro de compilação esperado), os existentes passam

### Fase 2 — Descriptor, estado e snapshot

- [x] Criar `android/src/main/kotlin/com/andre/video_ultra_player/TextOverlay.kt` com `internal data class TextOverlayDescriptor` (estilo do `AudioTrackDescriptor`, linha ~896 do controller): campos do contrato + `companion object fun from(map: Map<*, *>)` com `error(...)` quando `id`/`text` faltam e clamps; enum interno para `textAlign` (LEFT/CENTER/RIGHT)
- [x] No mesmo arquivo, função pura `internal fun textOverlaysForClip(overlays: List<TextOverlayDescriptor>, clipStartMs: Long, clipDurationMs: Long): List<TextOverlayDescriptor>` — filtra interseção com `[clipStartMs, clipStartMs + clipDurationMs)` e devolve cópias com janela re-ancorada (`startMs - clipStartMs` clampado, `endMs - clipStartMs` clampado pela duração)
- [x] Em `TimelineCompositionController.kt`: `private var textOverlays: List<TextOverlayDescriptor> = emptyList()`; incluir em `currentEditSnapshot()`/`restoreEditSnapshot()`; em `TimelineEditModel.kt`, adicionar `val textOverlays: List<TextOverlayDescriptor>` ao snapshot
- [x] Verificação: testes da Fase 1 de descriptor/snapshot passam (`./gradlew testDebugUnitTest`)

### Fase 3 — Renderização (TimelineTextOverlay + efeitos por clipe)

- [x] Em `TextOverlay.kt`, criar `internal class TimelineTextOverlay(descriptor, clipDurationMs) : androidx.media3.effect.TextOverlay()`:
  - `getText(presentationTimeUs)`: devolve `SpannableString("")` fora da janela `[startMs, endMs)` (convertendo µs→ms); dentro, `SpannableString(text)` com spans: `ForegroundColorSpan(color)`, `BackgroundColorSpan` (só se alpha > 0), `AbsoluteSizeSpan` (px = `fontSize` × altura do render), `AlignmentSpan.Standard` conforme `textAlign`, e `TypefaceSpan` custom (classe interna estendendo `MetricAffectingSpan` que aplica o `Typeface`) — `Typeface.createFromFile(fontPath)` com try/catch, senão `Typeface.create(fontFamily, NORMAL)`, fallback `Typeface.DEFAULT`
  - `getOverlaySettings(presentationTimeUs)`: `OverlaySettings` com âncora/offset NDC convertendo o centro `(x, y)` 0..1 top-left → NDC (-1..1, y invertido), `rotationDegrees` e `alpha = opacity`
  - > **Drift registrado (API media3 1.10.1):** `TextOverlay` estende `BitmapOverlay` e **não** declara `getOverlaySettings` — o posicionamento vem do override herdado de `TextureOverlay.getOverlaySettings`, retornando `StaticOverlaySettings.Builder().setOverlayFrameAnchor(x,y).setBackgroundFrameAnchor(x,y).setRotationDegrees(...).setAlphaScale(...)`. O construtor recebe `renderHeight` (px do `AbsoluteSizeSpan` = `fontSize` × `renderHeight`).
- [x] Em `TimelineCompositionController.kt`:
  - `buildTimelineComposition` ganha parâmetro `textOverlays: List<TextOverlayDescriptor> = emptyList()`; percorre os clipes acumulando `clipStartMs` (via `scaledDurationMs`) e chama `editedMediaItemFor(clip, renderSize, textOverlaysForClip(textOverlays, clipStartMs, clip.scaledDurationMs))`
  - `effectsFor` ganha o parâmetro de overlays do clipe e, se não vazio, adiciona **após** o `Presentation` (para o texto não ser cortado/escalado pelo crop): `OverlayEffect(ImmutableList.copyOf(clipOverlays.map { TimelineTextOverlay(it, clipDurationMs) }))` — importar `com.google.common.collect.ImmutableList`
  - > **Drift:** `OverlayEffect` recebe `List<TextureOverlay>` — passada a lista Kotlin direta (`clipOverlays.map { ... }`), pois `ImmutableList` Java quebra a inferência de overload.
  - Atualizar as 2 chamadas de `buildTimelineComposition` (`load`, `rebuildCompositionPreservingPlayback`) passando `textOverlays`
  - Export: `startExportCurrentTimeline` passa `textOverlays` para `exportFromClips` (novo parâmetro com default `emptyList()`), que repassa a `buildTimelineComposition`; `export(rawClips, ...)` (standalone) mantém `emptyList()` — paridade com áudio
  - Se o lint reclamar de API instável (`UnstableApi` em `TextOverlay`/`OverlayEffect`), adicionar `@androidx.annotation.OptIn(UnstableApi::class)` ou `@OptIn` nos pontos afetados (o arquivo já usa classes `@UnstableApi` do transformer sem anotação — seguir o que compilar)
- [x] Verificação: `./gradlew testDebugUnitTest` compila main + testes e passa

### Fase 4 — Mutações no controller + routing

- [x] Em `TimelineCompositionController.kt`, adicionar (após `removeAudioTrack`, linha ~256), seguindo o padrão snapshot → mutate → rebuild:
  - `fun addTextOverlay(rawOverlay: Map<*, *>)` — `pushEditSnapshot()`; `textOverlays = textOverlays + TextOverlayDescriptor.from(rawOverlay)`; `rebuildCompositionPreservingPlayback()`
  - `fun updateTextOverlay(rawOverlay: Map<*, *>)` — parse, substitui por `id` (no-op + `emitState()` se não existir, sem snapshot), rebuild
  - `fun removeTextOverlay(overlayId: String)` — no-op + `emitState()` se ausente; senão snapshot, remove, rebuild
- [x] Em `VideoUltraPlayerPlugin.kt`, adicionar 3 cases (após `"removeAudioTrack"`, linha ~210) com `withController`, extração de `args["overlay"] as? Map<*, *>` / `args["overlayId"] as? String`, `invalid_arguments` quando ausente, e `try/catch` com `Log.e` + `result.error("edit_failed", ..., Log.getStackTraceString(error))` no padrão do `setAudioTrack`
- [x] Verificação: `cd example/android && ./gradlew testDebugUnitTest` verde; `cd example && flutter build apk --debug` compila (build apenas — não instalar/executar)
  - > **Fix pré-existente (não relacionado à feature):** `VideoUltraPlayerPluginTest.onMethodCall_unknownMethod` falhava no HEAD (`Looper.getMainLooper() not mocked` no construtor). Corrigido tornando `mainHandler` do plugin `lazy` — comportamento preservado (Looper.getMainLooper é thread-safe), teste unitário volta a passar sem mock.
- [x] Checkpoint: commit das mudanças da parte + informar o usuário que a parte 3 está concluída e a parte 4 está pronta para execução

## Critérios de Sucesso

- [x] `./gradlew testDebugUnitTest` verde (incluindo `TextOverlayDescriptorTest`)
- [x] `flutter build apk --debug` compila
- [x] Preview e export usam o mesmo `buildTimelineComposition` com os mesmos overlays
- [x] Overlay fora da janela de qualquer clipe não renderiza nada (string vazia)
- [x] Undo/redo restauram textos junto com clipes e áudio
- [ ] _(manual — feito pelo usuário)_ Texto aparece/some na janela correta no preview e sai queimado no MP4

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Timestamps do overlay não são relativos ao item como assumido | Média | Função pura `textOverlaysForClip` isola a re-ancoragem — se a base mudar, só ela ajusta; validar no teste manual com 2 clipes |
| `OverlayEffect` com lista vazia ou string vazia quebra o pipeline | Baixa | Só adicionar o efeito quando `clipOverlays` não é vazio; string vazia é no-op de render |
| `Typeface.createFromFile` faz I/O por frame | Média | Cachear `Typeface` por path num `companion object` (mapa path→Typeface) dentro de `TimelineTextOverlay` |
| `textAlign`/baseline divergir do iOS | Média | Âncora = centro do texto nos dois lados; ajuste fino após teste manual |

## Rollback

`git revert` do commit do checkpoint da parte. Sem overlays, `buildTimelineComposition` recebe `emptyList()` e se comporta como antes.

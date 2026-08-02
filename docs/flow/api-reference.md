---
generated_at: 2026-08-02
source_commit: 21182b1
source_state: clean
verified_at: 2026-08-02
status: current
related_plans:
  - docs/plan/text-overlays/00-indice.md
---

# Flow: API Reference (superfície pública do plugin)

> **Resumo:** Catálogo completo da API pública de `video_ultra_player` — todo método de playback, edição, áudio, texto, thumbnail e export, com sua assinatura Dart, validações, nome no `MethodChannel`, payload e ponto de tratamento em iOS e Android.

## Visão Geral

Este flow não descreve uma feature: descreve a **superfície** que o app consumidor enxerga. Tudo o que o plugin oferece entra por uma única classe — `NativeTimelinePlayer` (`lib/src/native_timeline_player.dart`) — exportada pelo barrel `lib/video_ultra_player.dart` junto dos modelos serializáveis e enums.

Cada chamada pública atravessa as mesmas quatro camadas federadas: a API pública valida os argumentos e serializa os modelos para `Map<String, dynamic>`; o contrato abstrato `VideoUltraPlayerPlatform` define o método (com `UnimplementedError` como default); `MethodChannelVideoUltraPlayer` traduz para `invokeMethod` no canal `video_ultra_player/timeline_player`; e o plugin nativo (`VideoUltraPlayerPlugin.swift` / `VideoUltraPlayerPlugin.kt`) resolve o controller pelo `textureId` e executa a operação.

O `textureId` devolvido por `load` é a identidade da sessão: com exceção de `load`, `exportTimeline` e `generateThumbnails`, **todo método exige que `load` tenha completado** e envia o `textureId` no payload. Chamar qualquer um deles antes disso lança `StateError` já no Dart, via o guard privado `_requireTextureId()`.

As **25 operações do canal de métodos são implementadas nas duas plataformas** — a paridade iOS/Android está completa no commit analisado. Dois canais de eventos complementam a superfície: `.../events` (estado por `textureId`) e `.../export` (progresso de export, global).

## Passo a Passo

Trajeto de uma chamada qualquer, do app até o nativo — exemplificado com `setClipSpeed(1, 1.5)`:

1. **API pública** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.setClipSpeed`
   Valida os argumentos (`clipIndex >= 0`, `speed` em `[0.5, 2.0]`) e resolve a sessão com `_requireTextureId()`.
2. **Contrato abstrato** — `lib/video_ultra_player_platform_interface.dart` → `VideoUltraPlayerPlatform.setClipSpeed`
   Declara a assinatura na fronteira da plataforma; o corpo default só lança `UnimplementedError`.
3. **Implementação default** — `lib/video_ultra_player_method_channel.dart` → `MethodChannelVideoUltraPlayer.setClipSpeed`
   Chama `methodChannel.invokeMethod('setClipSpeed', {...})` com `textureId`, `clipIndex` e `speed`.
4. **Nativo iOS** — `ios/Classes/VideoUltraPlayerPlugin.swift:167` → `case "setClipSpeed"`
   Resolve o `TimelinePlayerController` no mapa `textureId → controller` e aplica a mutação.
   **Nativo Android** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt:178` → `"setClipSpeed" -> withController(...)`
   Mesmo papel, via o helper `withController`.
5. **Rebuild + eventos** — o nativo empurra um snapshot no histórico, muta a lista de clipes, reconstrói a composição preservando `textureId` e posição, e emite um novo `TimelinePlayerState` no canal `.../events`.

### Caminhos alternativos

- **Sessão não carregada:** `_requireTextureId()` lança `StateError('NativeTimelinePlayer.load must complete before this call.')` — nada chega ao canal.
- **Argumento inválido:** `ArgumentError` / `RangeError` são lançados no Dart antes do `invokeMethod` (ver tabela de validações).
- **`moveClip` com índices iguais:** curto-circuita em `Future<void>.value()` sem tocar o canal (`native_timeline_player.dart:266`).
- **Export concorrente:** `exportTimeline` e `exportCurrentTimeline` compartilham o flag `_exporting`; a segunda chamada lança `StateError('Only one timeline export can run at a time.')`.
- **`exportProgress` sem export ativo:** o getter lança `StateError` em vez de devolver um stream vazio.
- **Retorno nulo do nativo:** `load`, `exportTimeline` e `exportCurrentTimeline` lançam `StateError` se o canal não devolver, respectivamente, texture id ou output path (`video_ultra_player_method_channel.dart:38,56,71`).
- **`generateThumbnails` sem resultado:** o channel devolve `[]` em vez de lançar (`?? []`, linha 275).
- **`dispose` antes de `load`:** retorna cedo, sem chamar o canal — é seguro.

---

## Superfície pública

### `NativeTimelinePlayer` — construtor e getters

| Membro | Assinatura | Descrição |
|---|---|---|
| Construtor | `NativeTimelinePlayer({VideoUltraPlayerPlatform? platform})` | `platform` existe só para testes; produção usa `VideoUltraPlayerPlatform.instance`. |
| `textureId` | `int?` | Texture id da sessão; `null` antes de `load`. |
| `isLoaded` | `bool` | `true` quando `textureId != null`. |
| `stateStream` | `Stream<TimelinePlayerState>` | Broadcast do canal `.../events` (por `textureId`). Lança `StateError` sem `load`. |
| `exportProgress` | `Stream<TimelineExportProgress>` | Broadcast do canal `.../export`. Lança `StateError` se nenhum export está em curso. |

### Ciclo de vida e composição

| Método | Assinatura | Channel | Payload | Retorno |
|---|---|---|---|---|
| `load` | `Future<int> load(List<TimelineClip>, {TimelineCompositionConfig? config})` | `load` | `clips`, `config` | `textureId` |
| `dispose` | `Future<void> dispose()` | `dispose` | `textureId` | — |

`load` reseta o cache de `stateStream` e usa `TimelineCompositionConfig()` como default quando `config` é omitido.

### Playback

| Método | Assinatura | Channel | Payload |
|---|---|---|---|
| `play` | `Future<void> play()` | `play` | `textureId` |
| `pause` | `Future<void> pause()` | `pause` | `textureId` |
| `seekTo` | `Future<void> seekTo(Duration position)` | `seekTo` | `textureId`, `positionMs` |
| `seekToClip` | `Future<void> seekToClip(int clipIndex)` | `seekToClip` | `textureId`, `clipIndex` |
| `setVolume` | `Future<void> setVolume(double volume)` | `setVolume` | `textureId`, `volume` |

### Edição de clipes

| Método | Assinatura | Channel | Payload |
|---|---|---|---|
| `trimClip` | `Future<void> trimClip(int clipIndex, {Duration? trimStart, Duration? trimEnd})` | `trimClip` | `textureId`, `clipIndex`, `trimStartMs`, `trimEndMs` |
| `splitClip` | `Future<void> splitClip(int clipIndex, Duration atLocalPosition)` | `splitClip` | `textureId`, `clipIndex`, `atLocalPositionMs` |
| `insertClip` | `Future<void> insertClip(int atIndex, TimelineClip clip)` | `insertClip` | `textureId`, `atIndex`, `clip` |
| `removeClip` | `Future<void> removeClip(int clipIndex)` | `removeClip` | `textureId`, `clipIndex` |
| `moveClip` | `Future<void> moveClip(int fromIndex, int toIndex)` | `moveClip` | `textureId`, `fromIndex`, `toIndex` |
| `replaceClip` | `Future<void> replaceClip(int clipIndex, TimelineClip clip)` | `replaceClip` | `textureId`, `clipIndex`, `clip` |
| `setClipSpeed` | `Future<void> setClipSpeed(int clipIndex, double speed)` | `setClipSpeed` | `textureId`, `clipIndex`, `speed` |
| `setClipAlignment` | `Future<void> setClipAlignment(int clipIndex, double x, double y)` | `setClipAlignment` | `textureId`, `clipIndex`, `x`, `y` |
| `undo` | `Future<void> undo()` | `undo` | `textureId` |
| `redo` | `Future<void> redo()` | `redo` | `textureId` |

`trimStart`/`trimEnd` em `null` significam "manter o valor atual" — o payload envia `null` explicitamente. Em `setClipAlignment`, `x`/`y` usam o espaço de `Alignment`: `(-1,-1)` topo-esquerda, `(0,0)` centro, `(1,1)` base-direita.

### Trilha de áudio

| Método | Assinatura | Channel | Payload |
|---|---|---|---|
| `setAudioTrack` | `Future<void> setAudioTrack(AudioTrack track)` | `setAudioTrack` | `textureId`, `track` |
| `removeAudioTrack` | `Future<void> removeAudioTrack()` | `removeAudioTrack` | `textureId` |

### Text overlays

| Método | Assinatura | Channel | Payload |
|---|---|---|---|
| `addTextOverlay` | `Future<void> addTextOverlay(TimelineTextOverlay overlay)` | `addTextOverlay` | `textureId`, `overlay` |
| `updateTextOverlay` | `Future<void> updateTextOverlay(TimelineTextOverlay overlay)` | `updateTextOverlay` | `textureId`, `overlay` |
| `removeTextOverlay` | `Future<void> removeTextOverlay(String overlayId)` | `removeTextOverlay` | `textureId`, `overlayId` |

`updateTextOverlay` casa por `TimelineTextOverlay.id` (no-op quando o id não existe). Os três exigem `load` completo; no iOS o parse falho do overlay responde `FlutterError("invalid_arguments")` em vez de silenciar (`VideoUltraPlayerPlugin.swift` cases `addTextOverlay`/`updateTextOverlay`).

### Thumbnails

| Método | Assinatura | Channel | Payload | Retorno |
|---|---|---|---|---|
| `generateThumbnails` | `Future<List<String>> generateThumbnails(String videoPath, List<Duration> timestamps, {int width = 120})` | `generateThumbnails` | `videoPath`, `timestampsMs`, `width` | `List<String>` (caminhos de JPEG) |

Único método público que **não** exige `load` — é um utilitário autônomo, sem `textureId` no payload. O cache nativo é por `(videoPath, timestampMs, width)`.

### Export

| Método | Assinatura | Channel | Payload | Retorno |
|---|---|---|---|---|
| `exportTimeline` | `Future<String> exportTimeline(List<TimelineClip>, {String? outputPath, TimelineCompositionConfig? config})` | `exportTimeline` | `clips`, `outputPath`, `config` | caminho do MP4 |
| `exportCurrentTimeline` | `Future<String> exportCurrentTimeline({String? outputPath})` | `exportCurrentTimeline` | `textureId`, `outputPath` | caminho do MP4 |

`exportCurrentTimeline` é o que garante a regra "export = preview": reconstrói a partir do estado nativo já editado, sem receber lista de clipes.

---

## Modelos e enums exportados

Todos exportados por `lib/video_ultra_player.dart`.

### `TimelineClip` (`lib/src/models/timeline_clip.dart`)

Imutável, com `toJson`, `copyWith`, `==` e `hashCode`.

| Campo | Tipo | Default | Chave JSON | Nota |
|---|---|---|---|---|
| `path` | `String` | obrigatório | `path` | Caminho absoluto. |
| `type` | `MediaType` | obrigatório | `type` | Serializado por `.name`. |
| `duration` | `Duration?` | `null` | `durationMs` | Obrigatório na prática para imagens. |
| `alignment` | `Alignment` | `Alignment.center` | `alignment: {x, y}` | Pan-and-crop. |
| `scale` | `double` | `1.0` | `scale` | `assert(scale > 0)`. |
| `speed` | `double` | `1.0` | `speed` | `assert` em `[0.5, 2.0]`. Duração efetiva = `original / speed`. |
| `trimStart` | `Duration?` | `null` | `trimStartMs` | Omitido do JSON quando `null`. Ignorado para imagem. |
| `trimEnd` | `Duration?` | `null` | `trimEndMs` | **Ponto absoluto na fonte**, não duração; precede `duration` em vídeo. |
| `transitionToNext` | `ClipTransition?` | `null` | `transitionToNext` | Omitido quando `null`. |

### `TimelineCompositionConfig` (`.../timeline_composition_config.dart`)

Factory com validação (`baseWidth` deve ser positivo, senão `ArgumentError`) e construtor privado `._`. Campos: `aspectRatio` (`OutputAspectRatio`, default `original`) e `baseWidth` (`int`, default `1080`). Tem `toJson` e `copyWith`.

### `AudioTrack` (`.../audio_track.dart`)

| Campo | Tipo | Default | Chave JSON |
|---|---|---|---|
| `path` | `String` | obrigatório | `path` |
| `offset` | `Duration` | `Duration.zero` | `offsetMs` |
| `volume` | `double` | `1.0` (`assert` em `[0.0, 1.0]`) | `volume` |
| `trimStart` | `Duration?` | `null` | `trimStartMs` (omitido se nulo) |
| `trimEnd` | `Duration?` | `null` | `trimEndMs` (omitido se nulo) — ponto absoluto |
| `fadeIn` | `Duration?` | `null` | `fadeInMs` (omitido se nulo) |
| `fadeOut` | `Duration?` | `null` | `fadeOutMs` (omitido se nulo) |

### `TimelineTextOverlay` (`.../timeline_text_overlay.dart`)

Imutável, com `toJson` (ms no canal), `copyWith`, `==` e `hashCode`. Asserts no construtor: `x`/`y` em `[0.0, 1.0]`, `fontSize` em `(0.0, 1.0]`, `opacity` em `[0.0, 1.0]`. A ordenação `end > start` não é assertada em const (comparação de `Duration` não é const-evaluable) — é documentada e tratada pelo nativo/app.

| Campo | Tipo | Default | Chave JSON | Nota |
|---|---|---|---|---|
| `id` | `String` | obrigatório | `id` | Gerado pelo app; identidade de update/remove. |
| `text` | `String` | obrigatório | `text` | Multi-linha via `\n`. |
| `start` / `end` | `Duration` | obrigatórios | `startMs` / `endMs` | Janela na timeline `[start, end)`; `end` clampado pela duração total. |
| `x` / `y` | `double` | obrigatórios | `x` / `y` | Centro em fração do frame; `(0,0)` = canto superior esquerdo. |
| `rotationDegrees` | `double` | `0` | `rotationDegrees` | Graus. |
| `fontSize` | `double` | obrigatório | `fontSize` | Fração da altura do vídeo. |
| `color` | `int` | `0xFFFFFFFF` | `color` | ARGB. |
| `fontFamily` | `String?` | `null` | `fontFamily` | Fonte de sistema; omitida quando nula. |
| `fontPath` | `String?` | `null` | `fontPath` | `.ttf`/`.otf`; precedência sobre `fontFamily`; omitido quando nulo. |
| `backgroundColor` | `int` | `0x00000000` | `backgroundColor` | ARGB; alpha 0 = sem fundo. |
| `opacity` | `double` | `1.0` | `opacity` | `[0.0, 1.0]`. |
| `textAlign` | `TimelineTextAlign` | `center` | `textAlign` | Serializado por `.name` (`left`/`center`/`right`). |

### `TimelinePlayerState` (`.../timeline_player_state.dart`)

Recebido do canal `.../events` via `fromMap`. Tem também o construtor `.initial()` (tudo zerado/pausado) e `copyWith`.

| Campo | Tipo | Chave no evento |
|---|---|---|
| `globalPosition` | `Duration` | `globalPosition` (ms) |
| `clipIndex` | `int` | `clipIndex` |
| `localPosition` | `Duration` | `localPosition` (ms) |
| `isPlaying` | `bool` | `isPlaying` |
| `totalDuration` | `Duration` | `totalDuration` (ms) |
| `clipDurations` | `List<Duration>` | `clipDurationsMs` |
| `canUndo` / `canRedo` | `bool` | `canUndo` / `canRedo` |

### `TimelineExportProgress` (`.../timeline_export_progress.dart`)

`progress` (`double`, clampado em `[0.0, 1.0]` no `fromMap`) e `state` (`TimelineExportState`). Tem `.idle()` e `copyWith`.

### `ClipTransition` (`.../clip_transition.dart`)

`type` (`TransitionType`) e `duration` (`Duration`), com `toJson` (`type`, `durationMs`).

### `ClipThumbnail` (`.../clip_thumbnail.dart`)

`path` (`String`) e `time` (`Duration`), com `fromMap` (`path`, `timeMs`) e `toString`.

### `EditHistoryState` (`.../edit_history_state.dart`)

`canUndo` / `canRedo` (`bool`), com `fromMap`.

### Enums

| Enum | Arquivo | Valores |
|---|---|---|
| `MediaType` | `timeline_clip.dart` | `video`, `image` |
| `OutputAspectRatio` | `timeline_composition_config.dart` | `ratio16x9`, `ratio9x16`, `ratio1x1`, `original` |
| `TransitionType` | `clip_transition.dart` | `none`, `crossfade` |
| `TimelineExportState` | `timeline_export_progress.dart` | `idle`, `exporting`, `completed`, `failed` |
| `TimelineTextAlign` | `timeline_text_overlay.dart` | `left`, `center`, `right` |

---

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Barrel | `lib/video_ultra_player.dart` | Exporta a API pública e todos os modelos. |
| API pública | `lib/src/native_timeline_player.dart` | `NativeTimelinePlayer`: validações, serialização e delegação. |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | `VideoUltraPlayerPlatform`: assinaturas + `instance` com `PlatformInterface.verifyToken`. |
| Implementação default | `lib/video_ultra_player_method_channel.dart` | `MethodChannelVideoUltraPlayer`: `MethodChannel` + dois `EventChannel`. |
| Modelos | `lib/src/models/*.dart` | 8 modelos/enums serializáveis (tudo em milissegundos). |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | `handle(_:result:)` com os 25 `case`; controllers em `TimelinePlayerController`. |
| Nativo Android | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | `onMethodCall` com os mesmos 25 métodos; `withController` resolve o `textureId`. |
| Testes | `test/native_timeline_player_test.dart` | Validações da API pública com platform fake. |
| Testes | `test/video_ultra_player_method_channel_test.dart` | Nome do método e payload exato de cada comando. |
| Testes | `test/{timeline_clip,audio_track,timeline_text_overlay,timeline_player_state,timeline_export_progress,timeline_composition_config,clip_thumbnail,edit_history_state}_test.dart` | Serialização/desserialização dos modelos. |

## Regras de Negócio Relevantes

Validações que rodam **no Dart**, antes de qualquer `invokeMethod` — todas em `lib/src/native_timeline_player.dart` salvo indicação:

- **Sessão obrigatória** — `_requireTextureId()` (linha 371): tudo exceto `load`, `exportTimeline` e `generateThumbnails` lança `StateError` sem `load` completo.
- **Lista de clipes não vazia** — `load` e `exportTimeline` lançam `ArgumentError` para lista vazia.
- **Volume em `[0.0, 1.0]`** — `setVolume` lança `RangeError` fora da faixa.
- **Speed em `[0.5, 2.0]`** — `setClipSpeed` lança `RangeError`; `TimelineClip` reforça com `assert` no construtor.
- **Índices não negativos** — `trimClip`, `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip` e `setClipSpeed` lançam `ArgumentError` para índice `< 0`.
- **Split estritamente positivo** — `splitClip` exige `atLocalPosition > Duration.zero`.
- **`moveClip` idempotente** — índices iguais retornam sem tocar o canal.
- **Um export por vez** — flag `_exporting` compartilhado por `exportTimeline` e `exportCurrentTimeline`; liberado em `finally`.
- **`scale > 0`** — `assert` no construtor de `TimelineClip`.
- **`volume` de áudio em `[0.0, 1.0]`** — `assert` no construtor de `AudioTrack`.
- **`baseWidth` positivo** — `TimelineCompositionConfig` lança `ArgumentError` na factory.
- **Progresso clampado** — `TimelineExportProgress.fromMap` força `[0.0, 1.0]` e cai em `idle` para estado desconhecido.
- **Milissegundos no canal** — toda `Duration` vira `int` de milissegundos; `trimEnd` é ponto absoluto na fonte, não duração.

## Dependências Externas

- `plugin_platform_interface` — token de verificação de `VideoUltraPlayerPlatform.instance`.
- `flutter/services.dart` — `MethodChannel` / `EventChannel`.
- Canais: `video_ultra_player/timeline_player`, `video_ultra_player/timeline_player/events`, `video_ultra_player/timeline_player/export`.

## Observações

- **Paridade iOS/Android completa** no commit analisado: os 25 métodos do canal estão implementados nas duas plataformas.
- **`ClipTransition` não tem efeito visual.** É serializado por `TimelineClip.toJson`, mas o nativo lê apenas o `durationMs` — `TimelineComposition.swift:58` e `TimelineCompositionController.kt:877` guardam um `transitionToNextMs` e **descartam o `type`**; nenhuma plataforma aplica o crossfade. Todo limite entre clipes é corte seco e `TransitionType.crossfade` é, hoje, equivalente a `none`.
- **`ClipThumbnail` e `EditHistoryState` são modelos órfãos no caminho ativo.** `generateThumbnails` devolve `List<String>` (não `List<ClipThumbnail>`) e `canUndo`/`canRedo` chegam dentro de `TimelinePlayerState` — nenhum dos dois é construído pelo código do plugin, apesar de exportados publicamente.
- **`setClipAlignment` está fora do bloco "Editing operations"** em `native_timeline_player.dart` (aparece antes do separador de comentário), embora seja uma mutação de edição como as demais.
- **`VideoUltraPlayerPlatform` tem um cabeçalho `// ── Thumbnail generation ──` vazio** na linha 161, imediatamente seguido pelo bloco de áudio; `generateThumbnails` está declarado depois, sob o cabeçalho de áudio.
- Os doc comments dos modelos referenciam `NativeTimelinePlayer` e `TimelineClip` sem importá-los (`clip_thumbnail.dart`, `timeline_player_state.dart`, `audio_track.dart`, `timeline_composition_config.dart`), então esses links não resolvem na dartdoc gerada.
- Este documento cobre a **superfície**; o comportamento interno de cada operação está em [`native-timeline-player.md`](native-timeline-player.md), [`timeline-editing.md`](timeline-editing.md), [`timeline-export.md`](timeline-export.md), [`audio-track-overlay.md`](audio-track-overlay.md), [`text-overlay.md`](text-overlay.md) e [`thumbnail-generation.md`](thumbnail-generation.md).

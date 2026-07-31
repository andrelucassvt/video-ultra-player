---
generated_at: 2026-07-31
source_commit: 1e11b62
source_state: clean
verified_at: 2026-07-31
status: current
related_plans:
  - docs/plan/onda-1-quick-wins.md
---

# Flow: Edição de Clipes e Undo/Redo

> **Resumo:** Trim, split, insert, remove, move, replace, speed e alignment mutam a timeline já carregada sem perder o `textureId` nem a posição de playback, com histórico de undo/redo mantido no lado nativo.

## Visão Geral

Todas as operações de edição pressupõem uma timeline carregada: o método Dart valida o índice, chama `_requireTextureId()` e envia o comando com `textureId` + índice(s) pelo mesmo `MethodChannel` do player. Nada é reenviado — o nativo já tem a lista de clipes e muta a sua própria cópia.

No nativo, cada mutação obedece a três passos na mesma ordem, nas duas plataformas: **(1)** guardar um snapshot do modelo atual (lista de clipes + trilha de áudio externa) na pilha de undo; **(2)** aplicar a mutação na lista de clipes; **(3)** reconstruir a composição preservando playback. É o passo 3 que dá a sensação de edição "ao vivo": no iOS `rebuildPreservingPlayback` monta um `AVPlayerItem` novo, transfere o `AVPlayerItemVideoOutput` para ele, troca o item no `AVPlayer` e faz seek de tolerância zero para a posição anterior, retomando o play se estava tocando; no Android `rebuildCompositionPreservingPlayback` chama `setComposition(novaComposition, positionMs)` + `prepare()` e dá `play()` de volta. O `textureId` nunca muda, então o widget `Texture` do Flutter continua válido.

A única exceção é `setClipAlignment`: no iOS ele só recalcula o `AVVideoComposition` e o atribui ao item corrente (sem rebuild, sem interromper o player); no Android efeitos Media3 são imutáveis, então ele passa pelo rebuild completo como as outras operações. Essa é uma diferença real de comportamento entre plataformas — no Android arrastar o preview continuamente reconstrói a composição a cada chamada, e a UI deve commitar no fim do gesto.

O histórico vive em `TimelineEditModel` (Swift e Kotlin, implementações espelhadas): duas pilhas com limite de 50 snapshots, onde `pushSnapshot` sempre limpa o redo. `undo` tira o topo da pilha de undo, empurra o estado atual no redo e restaura; `redo` faz o inverso. Pilha vazia é no-op seguro que apenas re-emite estado. Os flags `canUndo`/`canRedo` viajam em cada evento de `TimelinePlayerState`, então a UI reflete a disponibilidade em tempo real sem consulta extra.

Split merece atenção porque é a operação que mais mexe na semântica de trim: o clipe é substituído por dois clipes que apontam para o mesmo arquivo, o primeiro com `trimEnd = trimStartEfetivo + atLocalPosition` e o segundo com `trimStart` nesse mesmo ponto. Como `trimEnd` é um ponto absoluto na fonte, o segundo pedaço herda o `trimEnd` original (ou o converte a partir de `durationMs`). O primeiro pedaço tem sua transição zerada — o limite do split é sempre corte seco.

## Passo a Passo

1. **Chamada Dart** — `lib/src/native_timeline_player.dart` → `trimClip` / `splitClip` / `insertClip` / `removeClip` / `moveClip` / `replaceClip` / `setClipSpeed` / `setClipAlignment`
   Validam índices (`ArgumentError` para negativos), faixa de speed (`RangeError`) e `atLocalPosition > 0`; `moveClip` com índices iguais é no-op em Dart.
2. **Contrato** — `lib/video_ultra_player_platform_interface.dart`
   Assinaturas com `textureId` explícito; `trimClip` aceita `trimStartMs`/`trimEndMs` nulos para "não mexer nesse lado".
3. **Serialização** — `lib/video_ultra_player_method_channel.dart`
   `invokeMethod` com `{textureId, clipIndex, …}`; `insertClip`/`replaceClip` mandam o clipe inteiro em `clip` (mapa de `TimelineClip.toJson`).
4. **Roteamento nativo** — `ios/Classes/VideoUltraPlayerPlugin.swift` (`switch`) / `.../VideoUltraPlayerPlugin.kt` (`when` + `withController`)
   Resolvem o controller pelo `textureId`; no iOS cada `case` de edição embrulha a chamada em `do/catch` e responde `edit_failed`.
5. **Snapshot** — `pushEditSnapshot()` → `TimelineEditModel.pushSnapshot`
   Guarda `clips` + `audioTrack` atuais e limpa a pilha de redo.
6. **Mutação do modelo** — `ios/Classes/TimelineComposition.swift` (`trimClip`, `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip`, `setClipSpeed`) / `.../TimelineCompositionController.kt` (mesmos nomes, operando em `MutableList<TimelineClip>`)
   Índices inválidos retornam sem alterar nada. `insertClip` faz clamp em `[0, count]`.
7. **Rebuild preservando playback** — `TimelinePlayerController.rebuildPreservingPlayback` (iOS) / `TimelineCompositionController.rebuildCompositionPreservingPlayback` (Android)
   iOS: novo `AVPlayerItem` → `texture.replacePlayerItem` → `player.replaceCurrentItem` → re-registra observer de fim → seek → `play()` se estava tocando.
   Android: `rebuildSegments()` → `setComposition(composition, positionMs)` → `prepare()` → `play()` se estava tocando.
8. **Emissão de estado** — `emitState()`
   Novas `clipDurationsMs`, novo `totalDuration`, `clipIndex`/`localPosition` recalculados e `canUndo`/`canRedo` atualizados.
9. **Undo/redo** — `NativeTimelinePlayer.undo` / `redo` → nativo `undo()` / `redo()`
   `makeEditSnapshot()` do estado atual → `editHistory.undo/redo(current:)` → `restoreEditSnapshot` → rebuild.
10. **Reflexo na UI** — `example/lib/editor/widgets/playback_bar.dart`
    Habilita os botões quando `state.canUndo && controller.canUndo` (o exemplo mantém um histórico local espelhado além do nativo).

### Caminhos alternativos

- **Sem `load`:** `_requireTextureId()` lança `StateError` antes do channel.
- **Índice negativo:** `ArgumentError.value(...)` em Dart; índices ≥ tamanho passam pelo Dart e são ignorados pelo nativo.
- **`splitClip` com posição ≤ 0:** `ArgumentError` em Dart; o nativo também ignora (`atLocalMs > 0` / `atLocalPositionMs <= 0`).
- **`speed` fora de `[0.5, 2.0]`:** `RangeError` em Dart; os nativos ainda fazem clamp.
- **Falha na mutação (iOS):** `edit_failed` com o erro em `details`; a exceção real vem do rebuild (`try composition.rebuildAsPlayerItem`).
- **Falha na mutação (Android):** só `insertClip`, `replaceClip` e `setAudioTrack` estão embrulhados em `try/catch` (`edit_failed`); as outras propagam a exceção pelo channel.
- **Pilha de histórico vazia:** `undo`/`redo` só chamam `emitState()`.
- **`removeClip` no último clipe restante:** o plugin permite; é o app que precisa impedir (o exemplo exige `clips.length > 1`).

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/src/native_timeline_player.dart` | Validação de argumentos e delegação |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | Assinaturas das operações de edição |
| Serialização | `lib/video_ultra_player_method_channel.dart` | Chaves `clipIndex`, `atIndex`, `fromIndex`, `toIndex`, `trimStartMs`, `trimEndMs`, `atLocalPositionMs`, `speed`, `clip` |
| Modelo | `lib/src/models/timeline_clip.dart` | Semântica de `trimStart`/`trimEnd`/`duration`/`speed` |
| Modelo | `lib/src/models/timeline_player_state.dart` | Transporta `clipDurations`, `canUndo`, `canRedo` |
| Modelo | `lib/src/models/edit_history_state.dart` | Par `canUndo`/`canRedo` isolado (não usado no caminho do channel) |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | `do/catch` por comando, `rebuildPreservingPlayback`, `pushEditSnapshot` |
| Nativo iOS | `ios/Classes/TimelineComposition.swift` | Mutação da lista de clipes e reconstrução da composição |
| Nativo iOS | `ios/Classes/TimelineEditModel.swift` | Pilhas de snapshot |
| Nativo Android | `.../TimelineCompositionController.kt` | Mutação da lista, rebuild, snapshots |
| Nativo Android | `.../TimelineEditModel.kt` | Pilhas de snapshot |
| Consumidor | `example/lib/editor/editor_controller.dart` | `trimClip`, `split`, `removeSelected`, `moveClip`, `setSelectedClipSpeed`, `undo`, `redo` e espelho local dos clipes |
| Consumidor | `example/lib/editor/widgets/clip_trim_handles.dart`, `clip_strip.dart`, `bottom_toolbar.dart`, `speed_sheet.dart` | Gestos que disparam as edições |
| Testes | `test/native_timeline_player_test.dart` | Cobre validações e delegação de cada operação |
| Testes | `test/video_ultra_player_method_channel_test.dart` | Cobre o payload enviado em cada comando |

## Regras de Negócio Relevantes

- **Edição preserva `textureId` e posição** — é o contrato central: `rebuildPreservingPlayback` / `rebuildCompositionPreservingPlayback` nunca re-registram a textura.
- **Snapshot antes da mutação** — `pushEditSnapshot()` é chamado antes de alterar o modelo em todas as operações, inclusive `setClipAlignment` e as de trilha de áudio.
- **`pushSnapshot` limpa o redo** — `TimelineEditModel` nas duas plataformas.
- **Histórico limitado a 50** — snapshots mais antigos são descartados (`removeFirst`).
- **Snapshot guarda metadados, não mídia** — `TimelineEditSnapshot` contém a lista de descritores de clipe e a trilha de áudio; nenhum arquivo é copiado.
- **`trimEnd` é ponto absoluto na fonte** — `trimClip` no iOS zera `durationMs` para deixar `trimEnd` como única fonte de duração; no Android `resolvedDurationMs` já dá precedência a `trimEndMs`.
- **Split gera corte seco** — o primeiro pedaço tem `transitionToNextMs = nil`.
- **Split converte `durationMs` em `trimEnd`** — no iOS quando `trimEndMs == nil` e havia `durationMs`; no Android o segundo pedaço herda `trimEndMs ?: sourceDurationMs`.
- **`moveClip` com índices iguais é no-op** — validado em Dart e nos dois nativos.
- **`insertClip` faz clamp do índice** — `max(0, min(index, count))` no iOS, `coerceIn(0, size)` no Android.
- **`setClipAlignment` clampa em `[-1, 1]`** — `updateAlignment` (iOS) e `coerceIn(-1.0, 1.0)` (Android).
- **`setClipSpeed` é rebuild completo** — documentado no Kotlin: chamar no commit do controle, não a cada tick de arrasto.

## Observações

- **Divergência iOS/Android em `setClipAlignment`:** inline no iOS, rebuild completo no Android. Efeito visível: no Android o preview reinicia o pipeline a cada chamada.
- **Divergência em tratamento de erro (Android):** só três comandos têm `try/catch`; uma exceção em `trimClip`, `splitClip`, `moveClip`, `removeClip` ou `setClipSpeed` sobe pelo channel sem código de erro dedicado.
- O app de exemplo mantém **dois** históricos: as pilhas nativas (fonte de `canUndo`/`canRedo`) e `_undoSnapshots`/`_redoSnapshots` em `EditorController`, que guardam a lista Dart de clipes e o índice selecionado. Os botões só habilitam quando ambos concordam, e um `undo` avança as duas pilhas em conjunto.
- `EditHistoryState` existe como modelo público e tem teste, mas nenhum caminho do channel o produz — os flags chegam dentro de `TimelinePlayerState`.
- Depois de qualquer edição o exemplo limpa `_thumbnailRequests`, porque as durações resolvidas mudam e as thumbnails são cacheadas por `(path, width, timestamps)`.

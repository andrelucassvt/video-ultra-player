---
generated_at: 2026-07-31
source_commit: 1e11b62
source_state: clean
verified_at: 2026-07-31
status: current
related_plans: []
---

# Flow: Trilha de Áudio Externa

> **Resumo:** Um arquivo de áudio é sobreposto à timeline carregada com offset, volume, trim e fades, misturado ao áudio dos clipes tanto no preview quanto no export.

## Visão Geral

O gatilho é `NativeTimelinePlayer.setAudioTrack(track)`, que exige uma timeline carregada. O modelo `AudioTrack` é imutável e serializa em milissegundos: `path`, `offsetMs`, `volume` e, quando presentes, `trimStartMs`, `trimEndMs`, `fadeInMs` e `fadeOutMs`. A semântica de trim espelha `TimelineClip`: `trimEnd` é um ponto absoluto no arquivo de origem, não uma duração. `volume` é validado por `assert` no construtor.

Só existe **uma** trilha externa por player: `setAudioTrack` substitui a anterior, `removeAudioTrack` volta ao áudio embutido dos clipes. As duas operações são tratadas como edição — entram no histórico de undo/redo e passam pelo rebuild que preserva `textureId` e posição.

No iOS, a trilha fica guardada no `TimelineComposition` (`currentAudioTrack`) e é aplicada dentro do `build`: uma terceira trilha de composição de áudio recebe o range da fonte inserido em `offsetTime`, com a duração clampada pelo tempo restante da timeline. O `AVAudioMix` é montado em `makeAudioMix`, que define volume 1.0 no início de cada segmento de áudio dos clipes e, para a trilha externa, aplica `setVolumeRamp` de 0→volume no fade-in, mantém o volume depois da rampa, e faz volume→0 na janela de fade-out calculada a partir do fim efetivo da região.

No Android a trilha vira uma **segunda sequência** Media3 (`audioSequenceFor`): `EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))` com um gap inicial equivalente ao offset, `ClippingConfiguration` para o trim e um `GainProcessor` alimentado por `AudioTrackGainProvider`, que calcula o ganho por posição de sample aplicando volume e as rampas de fade. A duração é capada para caber na timeline porque o Media3 exige que `durationUs` corresponda ao range de clipping.

Nos dois casos a trilha entra no `exportCurrentTimeline`, porque o export reconstrói a partir do mesmo estado. Já `exportTimeline(clips)` — a porta que não usa o player — exporta sem trilha externa.

## Passo a Passo

1. **Escolha do arquivo (app)** — `example/lib/editor/editor_controller.dart` → `addAudioTrack`
   `FilePicker.pickFiles(type: FileType.custom, allowedExtensions: [...])` com guarda `_isPicking`; cria `AudioTrack(path: path, volume: 0.8)`.
2. **Chamada Dart** — `lib/src/native_timeline_player.dart` → `setAudioTrack(track)`
   `_requireTextureId()` e `track.toJson()`.
3. **Serialização** — `lib/video_ultra_player_method_channel.dart` → `setAudioTrack` / `removeAudioTrack`
   `{textureId, track}` e `{textureId}`.
4. **Roteamento nativo (iOS)** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `case "setAudioTrack"`
   Converte o mapa em `AudioTrackDescriptor` (retorna sem responder se o path faltar) e chama `controller.setAudioTrack`.
   - **Android** — `.../VideoUltraPlayerPlugin.kt` → `case "setAudioTrack"`
     `try/catch` que loga com `Log.e` e devolve `edit_failed` com stack trace em `details`.
5. **Snapshot + aplicação (iOS)** — `TimelinePlayerController.setAudioTrack`
   `pushEditSnapshot()` → `composition.setAudioTrack(descriptor)` → `rebuildPreservingPlayback(positionMs:)`.
   - **Android** — `TimelineCompositionController.setAudioTrack`
     `pushEditSnapshot()` → `resolveAudioTrack` (descobre `sourceDurationMs` com `MediaMetadataRetriever`) → `rebuildCompositionPreservingPlayback()`.
6. **Inserção na composição (iOS)** — `ios/Classes/TimelineComposition.swift` → bloco `if let extTrack = currentAudioTrack` em `build`
   Nova trilha de áudio, `sourceStart` do trim, duração do trim ou do restante do asset, clamp por `totalDuration - offset`.
7. **Mixagem (iOS)** — `makeAudioMix(externalAudioTrack:externalDescriptor:timelineEnd:)`
   Volume no offset (ou rampa de fade-in) e rampa de fade-out antes do fim efetivo.
8. **Sequência de áudio (Android)** — `audioSequenceFor(track, timelineDurationMs)`
   `addGap(offsetMs * 1000)` quando há offset, clipping `[trimStart, trimStart + duraçãoEfetiva]`, `setRemoveVideo(true)`, `setDurationUs`.
9. **Ganho e fades (Android)** — `AudioTrackGainProvider.getGainFactorAtSamplePosition`
   Converte sample → µs e multiplica o volume pelas rampas lineares de fade-in/fade-out.
10. **Reflexo no estado** — `emitState()` após o rebuild
    Duração total e `clipDurationsMs` não mudam (a trilha não estende a timeline), mas `canUndo` passa a `true`.
11. **UI da trilha** — `example/lib/editor/widgets/audio_track_row.dart`
    Estado vazio com botão "Adicionar audio"; trilha ativa posicionada por `offset * pixelsPerSecond`, com slider de volume (`setAudioVolumePreview` durante o arrasto, `commitAudioVolume` no release) e ação de remover.
12. **Remoção** — `NativeTimelinePlayer.removeAudioTrack` → nativo
    iOS: `clearAudioTrack()` + `rebuildPreservingPlayback(clearAudioTrack: true)`. Android: `audioTrack = null` + rebuild.
13. **Export** — `exportCurrentTimeline`
    Reconstrói com a trilha ativa (`buildCurrentExportAsset` no iOS, `startExportCurrentTimeline` no Android).

### Caminhos alternativos

- **Sem `load`:** `setAudioTrack`/`removeAudioTrack` lançam `StateError` em Dart.
- **`volume` fora de `[0.0, 1.0]`:** `assert` no construtor de `AudioTrack` (só em debug); os nativos fazem clamp de qualquer forma.
- **Path inválido no mapa:** iOS retorna sem responder (o `guard` do `case` falha); Android lança em `AudioTrackDescriptor.from` e o `catch` devolve `edit_failed`.
- **Arquivo sem trilha de áudio (iOS):** `extAudioAsset.tracks(withMediaType: .audio).first` falha e a trilha é silenciosamente ignorada — o rebuild acontece sem áudio externo.
- **Offset além do fim da timeline:** iOS calcula `timelineRemaining` negativo e não insere nada; Android nem cria a sequência (`offsetMs < timelineDurationMs`).
- **`removeAudioTrack` sem trilha:** no-op que apenas re-emite estado (sem snapshot, sem rebuild).
- **Picker cancelado (app):** `addAudioTrack` retorna sem alterar a timeline; `PlatformException` com código `multiple_request` é ignorada.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Modelo | `lib/src/models/audio_track.dart` | Campos, `toJson`, `copyWith`, igualdade |
| API pública | `lib/src/native_timeline_player.dart` | `setAudioTrack`, `removeAudioTrack` |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | Assinaturas com `textureId` |
| Serialização | `lib/video_ultra_player_method_channel.dart` | `{textureId, track}` / `{textureId}` |
| Nativo iOS | `ios/Classes/TimelineComposition.swift` | `AudioTrackDescriptor`, inserção da trilha, `makeAudioMix` |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | Roteamento, snapshot, rebuild com `clearAudioTrack` |
| Nativo Android | `.../TimelineCompositionController.kt` | `AudioTrackDescriptor`, `audioSequenceFor`, `AudioTrackGainProvider`, `resolveAudioTrack` |
| Nativo Android | `.../VideoUltraPlayerPlugin.kt` | Roteamento com `try/catch` e log |
| Histórico | `ios/Classes/TimelineEditModel.swift`, `.../TimelineEditModel.kt` | `TimelineEditSnapshot` inclui a trilha |
| Consumidor | `example/lib/editor/editor_controller.dart` | `addAudioTrack`, `setAudioTrack`, volume preview/commit, `removeAudioTrack` |
| Consumidor | `example/lib/editor/widgets/audio_track_row.dart` | Faixa de áudio na timeline |
| Testes | `test/audio_track_test.dart` | Serialização, defaults, `copyWith`, igualdade |
| Testes | `test/native_timeline_player_test.dart`, `test/video_ultra_player_method_channel_test.dart` | Delegação e payload |

## Regras de Negócio Relevantes

- **Uma trilha externa por player** — `currentAudioTrack` (iOS) e `audioTrack` (Android) são campos únicos; `setAudioTrack` substitui.
- **Exige `load`** — `_requireTextureId()` em ambos os métodos Dart.
- **`trimEnd` é ponto absoluto na fonte** — documentado em `audio_track.dart` e implementado nos dois nativos (`effectiveTrimEndMs` no Android).
- **Duração é capada pela timeline** — iOS: `CMTimeMinimum(sourceDuration, totalDuration - offset)`. Android: `min(trimmedDurationMs, timelineDurationMs - offsetMs)`, exigido pelo Media3 (`durationUs` deve casar com o range de clipping).
- **`volume` clampado em `[0.0, 1.0]`** — `assert` em Dart, `max/min` no iOS, `coerceIn` no Android.
- **Fades são lineares** — `setVolumeRamp` no iOS; ganho proporcional por sample no Android.
- **A trilha entra no histórico** — `pushEditSnapshot()` antes de aplicar, e `TimelineEditSnapshot` carrega a trilha junto com os clipes; um `undo` restaura ambos.
- **A trilha não estende a timeline** — a duração total continua sendo a soma dos clipes; áudio além disso é cortado.
- **`exportCurrentTimeline` inclui a trilha; `exportTimeline(clips)` não** — a segunda porta cria composição nova sem trilha externa.

## Dependências Externas

- **iOS:** `AVURLAsset`, `AVMutableCompositionTrack`, `AVMutableAudioMix`, `AVMutableAudioMixInputParameters`.
- **Android:** `androidx.media3.common.audio.GainProcessor`, `EditedMediaItemSequence` com `C.TRACK_TYPE_AUDIO`, `MediaItem.ClippingConfiguration`, `MediaMetadataRetriever`.
- **App de exemplo:** `file_picker ^11.0.2` para escolher o arquivo de áudio.

## Observações

- No iOS um arquivo sem trilha de áudio é ignorado sem erro: o rebuild ocorre, `currentAudioTrack` fica preenchido, mas nenhum som é adicionado. O Dart recebe sucesso.
- `resolveAudioTrack` (Android) faz I/O de metadados na thread do channel.
- Os `fadeIn`/`fadeOut` só existem para a trilha externa; o áudio dos clipes recebe volume fixo 1.0 no início de cada segmento (iOS) e nenhum processador de ganho (Android).
- O `AudioTrackRow` do exemplo desenha a trilha com largura mínima de 220 px, então o bloco na timeline não representa a duração real do áudio.
- `AudioTrack.trimStart`/`trimEnd`/`fadeIn`/`fadeOut` não são expostos pela UI do exemplo — só `path`, `offset` (sempre zero) e `volume`.

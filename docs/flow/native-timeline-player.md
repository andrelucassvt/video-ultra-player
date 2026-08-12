---
generated_at: 2026-07-31
source_commit: 1e11b62
source_state: clean
verified_at: 2026-07-31
status: current
related_plans:
  - docs/plan/onda-1-quick-wins.md
---

# Flow: Native Timeline Player (load → preview → playback)

> **Resumo:** O app entrega uma lista de `TimelineClip` ao plugin, o nativo constrói uma composição única e devolve um `textureId`; o Flutter desenha esse texture e recebe posição/estado de playback por stream.

## Visão Geral

O gatilho é `NativeTimelinePlayer.load(clips, config:)`. A API pública valida o que dá para validar em Dart (lista não vazia) e converte cada `TimelineClip` em mapa via `toJson()`, com todas as durações em milissegundos. A chamada segue para `VideoUltraPlayerPlatform.instance`, cuja implementação default (`MethodChannelVideoUltraPlayer`) invoca o método `load` no canal `video_ultra_player/timeline_player` com `{'clips': [...], 'config': {...}}`.

O nativo monta a composição inteira de uma vez — uma trilha de vídeo com todos os clipes inseridos em sequência no iOS, uma `EditedMediaItemSequence` no Android — registra uma textura no `TextureRegistry` da engine e devolve o id dessa textura como resultado do método. Esse `int` fica em `NativeTimelinePlayer._textureId` e passa a ser a identidade da sessão: todos os comandos seguintes (`play`, `seekTo`, `trimClip`, `exportCurrentTimeline`, `dispose`) levam o `textureId` no mapa de argumentos, e o plugin nativo resolve o controller correspondente em seu dicionário `textureId → controller`.

Com o id em mãos a UI monta um `Texture(textureId: ...)`. O primeiro acesso a `NativeTimelinePlayer.stateStream` abre o `EventChannel` `.../events` passando o `textureId` como argumento de `onListen`; o nativo guarda o `eventSink` no controller certo e emite um estado imediatamente. A partir daí o estado chega periodicamente (observer de 1/30 s no iOS, `Handler` de 33 ms no Android) e também logo depois de cada comando, sempre no mesmo mapa que `TimelinePlayerState.fromMap` decodifica: posição global, índice do clipe atual, posição local dentro do clipe, `isPlaying`, duração total, durações resolvidas de cada clipe e os flags `canUndo`/`canRedo`.

Playback é repasse direto: `play`, `pause`, `seekTo` (posição global em ms), `seekToClip` (converte índice em tempo de início consultando os segmentos) e `setVolume`. O seek usa tolerância zero no iOS para ficar frame-accurate. O fim da timeline não faz loop: no iOS a notificação `AVPlayerItemDidPlayToEndTime` pausa o player e emite estado; no Android o player apenas para no fim da composição.

Quando o player não é mais necessário, `dispose()` limpa o estado Dart, remove o controller do mapa nativo e libera texture, player e arquivos temporários. Depois disso qualquer chamada volta a lançar `StateError` até um novo `load`.

## Passo a Passo

1. **API pública** — `lib/src/native_timeline_player.dart` → `NativeTimelinePlayer.load`
   Rejeita lista vazia com `ArgumentError`, serializa os clipes e aplica `TimelineCompositionConfig()` default quando `config` é `null`.
2. **Platform interface** — `lib/video_ultra_player_platform_interface.dart` → `VideoUltraPlayerPlatform.load`
   Contrato abstrato; a implementação usada vem de `VideoUltraPlayerPlatform.instance`.
3. **Method channel** — `lib/video_ultra_player_method_channel.dart` → `MethodChannelVideoUltraPlayer.load`
   `invokeMethod<int>('load', {'clips', 'config'})`; lança `StateError` se o nativo devolver `null`.
4. **Plugin nativo (iOS)** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `load(_:result:)`
   Exige `textureRegistry` (erro `not_attached` sem ele), converte os mapas em `TimelineClipDescriptor` (erro `invalid_clip` se algum falhar) e chama `TimelinePlayerController.make(...)`, que monta a composição fora da thread da plataforma e responde pelo `completion`.
   - **Plugin nativo (Android)** — `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` → `load(call, result)`
     Exige `applicationContext` + `textureRegistry` e delega a `TimelineCompositionController.load(clips, config, onReady, onError)`, que resolve os metadados num pool de background e volta para a main só para criar textura e player.
5. **Construção da composição** — `ios/Classes/TimelineComposition.swift` → `build` / `.../TimelineCompositionController.kt` → `buildTimelineComposition`
   Insere os clipes em sequência, aplica trim, speed, alinhamento/escala e resolve o `renderSize` a partir do `config`.
6. **Registro da textura** — `ios/Classes/TimelineTexture.swift` + `FlutterTextureRegistry.register` / `textureRegistry.createSurfaceTexture()` + `Surface` no Android
   O id devolvido por esse registro é o valor que volta ao Dart.
7. **Guarda do controller** — `controllers[textureId] = controller` nas duas plataformas
   `result(controller.textureId)` / `result.success(textureId)` encerra o `load`.
8. **Render no Flutter** — `example/lib/editor/widgets/preview_area.dart` → `Texture(textureId: controller.textureId!)`
   Enquanto `textureId` é `null`, exibe `_PreviewPlaceholder`.
9. **Abertura do stream de estado** — `NativeTimelinePlayer.stateStream` → `MethodChannelVideoUltraPlayer.stateStream`
   `eventChannel.receiveBroadcastStream({'textureId': ...})`, mapeado por `TimelinePlayerState.fromMap` e convertido em broadcast (cacheado em `_stateStream`).
10. **Emissão de estado (nativo)** — `TimelinePlayerController.emitState` (iOS) / `TimelineCompositionController.emitState` (Android)
    Publica `globalPosition`, `clipIndex`, `localPosition`, `isPlaying`, `totalDuration`, `clipDurationsMs`, `canUndo`, `canRedo`.
11. **Comandos de playback** — `play` / `pause` / `seekTo` / `seekToClip` / `setVolume`
    Cada um resolve o controller pelo `textureId` (erro `not_found` se não existir) e emite estado ao final. `seekToClip` usa `TimelineComposition.startTime(forClipIndex:)` no iOS e `segments.getOrNull(clipIndex)?.startMs` no Android.
12. **Troca de resolução/proporção** — `NativeTimelinePlayer.setCompositionConfig`
    Caminho dedicado que evita o ciclo `dispose` + `load`: no-op se a config não mudou, senão manda `{'textureId', 'config'}` pelo channel. No iOS só a `AVVideoComposition` é re-gerada e reatribuída ao item (`TimelineComposition.updateConfig`); no Android a `Composition` é reconstruída (efeitos Media3 são imutáveis), mas player, `Surface` e `textureId` são reaproveitados. Nas duas plataformas clipes, textos, trilha de áudio, histórico nativo e posição de playback sobrevivem, e nada é redecodificado.
13. **Encerramento** — `NativeTimelinePlayer.dispose`
    Zera `_textureId`, `_stateStream` e `_config` antes de chamar o nativo, que remove o controller do mapa e libera player, textura e arquivos temporários.

### Caminhos alternativos

- **`load` não chamado:** qualquer método de player passa por `_requireTextureId()` e lança `StateError('NativeTimelinePlayer.load must complete before this call.')`.
- **Plugin sem texture registry / contexto:** `load` responde erro `not_attached`.
- **Clipe inválido:** iOS devolve `invalid_clip` quando algum `TimelineClipDescriptor(dictionary:)` retorna `nil`; no Android `TimelineClip.from` lança e o `catch` converte em `load_failed`.
- **Falha ao montar a composição:** `load_failed` com os detalhes do erro nativo.
- **`textureId` inexistente:** `not_found` (`No native timeline player exists for textureId …`).
- **Erro de playback no Android:** `Player.Listener.onPlayerError` empurra `events.error("playback_error", …)` pelo próprio `EventChannel` de estado — chega como erro do stream, não como exceção do método. `EditorScreen._capturePlaybackError` é quem trata isso no exemplo.
- **`setVolume` fora de faixa:** `NativeTimelinePlayer.setVolume` lança `RangeError` antes de tocar o channel.
- **`dispose` sem `load`:** retorna sem chamar o nativo.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/src/native_timeline_player.dart` | Validações, cache dos streams, ciclo de vida do `textureId` |
| API pública (barrel) | `lib/video_ultra_player.dart` | Exporta player e modelos |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | Assinaturas abstratas de todas as operações |
| Serialização | `lib/video_ultra_player_method_channel.dart` | Nomes de canal/método e chaves dos argumentos |
| Modelos | `lib/src/models/timeline_clip.dart`, `timeline_composition_config.dart`, `timeline_player_state.dart` | Entrada da composição e estado devolvido |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | Roteamento de métodos, mapa de controllers, stream handler de estado |
| Nativo iOS | `ios/Classes/TimelineComposition.swift` | `AVMutableComposition`, segmentos, `renderSize`, transform por clipe |
| Nativo iOS | `ios/Classes/TimelineTexture.swift` | `AVPlayerItemVideoOutput` + `CADisplayLink` → `copyPixelBuffer` |
| Nativo Android | `.../VideoUltraPlayerPlugin.kt` | Roteamento de métodos, mapa de controllers, stream handlers |
| Nativo Android | `.../TimelineCompositionController.kt` | `CompositionPlayer`, `Surface`, segmentos, emissão de estado |
| Consumidor | `example/lib/editor/editor_controller.dart` | `replaceTimeline`, `playOrPause`, seek com throttle |
| Consumidor | `example/lib/editor/widgets/preview_area.dart`, `editor_toolbar.dart` | `Texture` e controles de playback |
| Testes | `test/native_timeline_player_test.dart` | Todas as chamadas contra um `VideoUltraPlayerPlatform` fake |
| Testes | `test/video_ultra_player_method_channel_test.dart` | Nomes de método e payloads enviados ao canal |
| Testes | `test/timeline_player_state_test.dart`, `test/timeline_clip_test.dart` | Decodificação de estado e serialização de clipe |

## Regras de Negócio Relevantes

- **Timeline não pode ser vazia** — `lib/src/native_timeline_player.dart`: `load` e `exportTimeline` lançam `ArgumentError`; no Android `parseTimelineClips` reforça com `require(rawClips.isNotEmpty())`.
- **`textureId` é a identidade da sessão** — os plugins nativos resolvem o controller por ele; sem `load` não há id e a chamada falha em Dart.
- **`volume` em `[0.0, 1.0]`** — validado em Dart (`RangeError`) e reforçado no nativo (`min/max` no iOS, `coerceIn` no Android).
- **`speed` em `[0.5, 2.0]`** — `assert` no construtor de `TimelineClip`, `RangeError` em `setClipSpeed`, clamp nos dois nativos.
- **`trimEnd` é ponto absoluto na fonte, não duração** — documentado em `timeline_clip.dart` e implementado em `effectiveRange` (iOS) / `resolvedDurationMs` (Android); tem precedência sobre `duration` para vídeo.
- **Clipes de imagem ignoram trim** — usam `duration` (fallback 2000 ms) e viram vídeo: MP4 via `AVAssetWriter` no iOS (encodado uma vez por processo pelo `ImageClipVideoCache`, a 6 fps e com o lado maior limitado a 1920 px), `setImageDurationMs` + `setFrameRate(30)` no Android.
- **`clipDurations` reflete a duração exibida** — já com speed aplicado (`scaledVideoDuration` no iOS, `scaledDurationMs` no Android).
- **Fim da timeline não faz loop** — `didPlayToEnd` pausa no iOS; para tocar de novo o app precisa dar seek para zero (é o que `EditorController.playOrPause` faz ao detectar posição no fim).
- **`renderSize` vem do `config`** — `original` usa o tamanho normalizado do primeiro clipe, considerando rotação; as outras proporções derivam de `baseWidth`, sempre arredondado para dimensão par. Overlays e legendas usam esse mesmo canvas.
- **Config de saída é trocada no lugar, não recarregada** — `setCompositionConfig` preserva `textureId` e todo o estado editado; `load` continua sendo só para trocar a timeline de fato. A config aplicada fica em `NativeTimelinePlayer.compositionConfig` e alimenta o `exportCurrentTimeline`, então "export = preview" continua valendo depois da troca.
- **Config também define HDR e fidelidade** — no Android, `TimelineHdrMode` escolhe manter HDR ou fazer tone mapping para SDR via MediaCodec; o iOS preserva seu pipeline nativo de cor. `preserveSourceQuality` solicita bitrate/frame rate da origem durante o re-encode, com fallback do encoder quando necessário.
- **Config de saída não entra no histórico** — nenhuma plataforma empurra snapshot em `setCompositionConfig`; undo não deve reverter proporção.
- **Estado trafega em milissegundos** — o nativo emite números e `TimelinePlayerState.fromMap` converte para `Duration`.

## Dependências Externas

- **iOS:** AVFoundation (`AVMutableComposition`, `AVPlayer`, `AVPlayerItemVideoOutput`), QuartzCore (`CADisplayLink`), UIKit.
- **Android:** `androidx.media3` 1.10.1 (`CompositionPlayer`, `EditedMediaItem`, `Presentation`, `Crop`), `MediaMetadataRetriever`.
- **Flutter engine:** `FlutterTextureRegistry` (iOS) e `io.flutter.view.TextureRegistry` (Android).

## Observações

- `stateStream` é cacheado por instância e só é invalidado em `load`/`dispose`.
- No Android o estado é emitido por polling com cadência adaptativa (33 ms tocando, 250 ms pausado); no iOS o `addPeriodicTimeObserver` só dispara com o player andando, então cada comando chama `emitState()` explicitamente para cobrir o resto.
- As duas plataformas deduplicam o estado antes de cruzar o canal (comparam com o último payload emitido) e `NativeTimelinePlayer.stateStream` ainda aplica `.distinct()` em Dart, então um player parado não acorda a árvore de widgets.
- `TimelineTexture.observeInitialItemReady` faz um seek de tolerância zero na primeira vez que o item fica `readyToPlay`: sem isso o `AVPlayerItemVideoOutput` não entrega frame algum enquanto pausado e a `Texture` fica preta.
- `TimelinePlayerState.clipDurations` pode vir vazio antes do primeiro estado nativo; `EditorController.resolvedClipDurations` cai num cálculo local nesse caso.
- Não há teste automatizado do caminho nativo — a cobertura Dart usa um platform fake e `android/src/test/.../VideoUltraPlayerPluginTest.kt` só cobre `notImplemented()`.

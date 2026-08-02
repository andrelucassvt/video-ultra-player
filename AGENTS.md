# video_ultra_player

Plugin Flutter federado (Dart + iOS/Swift + Android/Kotlin) que compõe uma sequência de clipes em **uma única composição nativa** — preview gapless renderizado em `Texture` e export MP4 do mesmo estado editado.

## Stack

- Dart `^3.11.5` / Flutter `>=3.3.0`; dependência runtime: `plugin_platform_interface`
- iOS: Swift 5.0, target 13.0, **AVFoundation** (`AVMutableComposition` + `AVPlayerItemVideoOutput`)
- Android: Kotlin 2.2.20, Gradle **Kotlin DSL**, `compileSdk 36`, `minSdk 24`, JVM 17, **`androidx.media3` 1.10.1** (`CompositionPlayer` + `Transformer`)

## Arquitetura

```
NativeTimelinePlayer → VideoUltraPlayerPlatform → MethodChannelVideoUltraPlayer
                                                    └→ iOS / Android (pluginClass)
```

- `load` devolve um `textureId`; ele é a identidade da sessão — todo comando seguinte manda `textureId` e o nativo resolve o controller no mapa `textureId → controller`.
- Preview e export compartilham o mesmo estado nativo: `exportCurrentTimeline` reconstrói a partir da lista de clipes já editada, então o MP4 é exatamente o que o preview mostra.
- Canais: `video_ultra_player/timeline_player` (comandos), `.../events` (estado, por `textureId`), `.../export` (progresso, global).

## Estrutura

- `lib/src/native_timeline_player.dart` — API pública (validações + delegação)
- `lib/src/models/` — modelos serializáveis (tudo em milissegundos no channel)
- `lib/video_ultra_player_platform_interface.dart` — contrato abstrato
- `lib/video_ultra_player_method_channel.dart` — implementação default via channels
- `ios/Classes/` — plugin, composição, textura, histórico, thumbnails
- `android/src/main/kotlin/com/andre/video_ultra_player/` — mesmos papéis em Kotlin
- `example/` — app editor que consome o plugin (`ChangeNotifier`, sem DI/router)
- `test/` — testes Dart (modelos, player com platform fake, payloads do channel)
- `docs/plan/` — planos de implementação; `docs/flow/` — flows documentados

## Comandos

- `flutter analyze` — lint/análise estática
- `flutter test` — testes unitários Dart
- `cd example/android && ./gradlew testDebugUnitTest` — testes Kotlin do plugin

## Convenções

- Toda capacidade nova é federada nas quatro camadas: `platform_interface` → `method_channel` → iOS **e** Android. A API pública nunca instancia `MethodChannel`.
- Nome do channel = nome do pacote (`video_ultra_player/...`). **Nunca** `com.luma_vid/...` (resíduo de outro contexto).
- Toda mutação nativa segue: `pushEditSnapshot()` → mutar a lista de clipes → rebuild preservando `textureId` e posição (`rebuildPreservingPlayback` / `rebuildCompositionPreservingPlayback`).
- Durações trafegam sempre em milissegundos; `trimEnd` é **ponto absoluto na fonte**, não duração, e tem precedência sobre `duration` para vídeo.
- Android é Kotlin DSL (`build.gradle.kts`) — edite `dependencies {}` em sintaxe Kotlin, não Groovy.
- Toda funcionalidade nova ou ajuste em funcionalidade existente deve priorizar **desempenho fluido em todas as plataformas** (sem jank, sem trabalho pesado na thread de UI) e **simplicidade de uso para o usuário final** (menos passos, menos fricção, UX clara).
- Antes de criar ou alterar features, invoque a skill `brainstorming`.
- Não criar arquivos `.md` para documentar mudanças de código.

## Gotchas

- `AVPlayerLayer` (iOS) e `SurfaceView` (Android) **não** são capturáveis para textura: use `AVPlayerItemVideoOutput.copyPixelBuffer` e o `SurfaceTexture` do `TextureRegistry`.
- iOS: o `AVPlayerItemVideoOutput` precisa ser anexado ao item **antes** de entregá-lo ao `AVPlayer`, e um seek de tolerância zero no primeiro `readyToPlay` é o que faz o primeiro frame aparecer com o player pausado.
- Android: efeitos Media3 são imutáveis — até `setClipAlignment` exige rebuild da `Composition`. Chame comandos de edição só no commit do gesto, nunca a cada tick de arrasto.
- Android: `EditedMediaItem.setDurationUs` precisa receber a duração **da fonte**, não a cortada, senão o Media3 rejeita `clippingEndPositionMs`.
- iOS: a trilha de áudio da composição só deve ser criada se algum clipe tiver áudio (guard `hasAnyClipAudio`) — sem isso o load falha silenciosamente.
- `ClipTransition`/`crossfade` é serializado e parseado, mas **nenhuma plataforma o aplica**: todo limite entre clipes é corte seco.
- `ClipThumbnail` e `EditHistoryState` são modelos públicos sem caminho ativo no channel (`generateThumbnails` devolve `List<String>`; `canUndo`/`canRedo` chegam em `TimelinePlayerState`).
- Não recrie aqui a Clean Architecture de app (`presentation/domain/data`, Cubits, GetIt, GoRouter) — este repo é um plugin.
- Android: timestamps de overlay/efeito no Media3 são **relativos ao `EditedMediaItem`, não à timeline** — re-ancore a janela por clipe (`textOverlaysForClip`) subtraindo o `clipStartMs` do segmento.
- Android: `Typeface.createFromFile` faz I/O por frame — cacheie o `Typeface` por path (`companion object`); fonte custom inválida deve cair em fallback, nunca falhar o load.
- iOS: a janela de um `CATextLayer` no CoreAnimationTool é expressa por `beginTime`/`duration`/`fillMode` do próprio layer (`isRemovedOnCompletion` é de `CAAnimation`, não existe em `CALayer`); se o texto vazar a janela no teste manual, use keyframe de `opacity` ancorado em `AVCoreAnimationBeginTimeAtZero` (fallback documentado em `TextOverlayLayers.swift`).
- iOS: além do rebuild completo (`rebuildPreservingPlayback`), mutações de texto usam o rebuild **cirúrgico** da `videoComposition` (`applyUpdatedVideoComposition`) — re-gera só a videoComposition e reatribui ao item, com seek de tolerância zero + `texture.requestFrame()` se pausado.

## Não fazer

- Não usar `print()` — use `log()` de `dart:developer`.
- Não rodar `flutter pub upgrade` sem perguntar.
- Não implementar uma capacidade em só uma plataforma sem alinhar — a paridade iOS/Android faz parte do contrato.
- Não quebrar a regra "export = preview": qualquer efeito novo tem de viver no pipeline compartilhado pelas duas operações.

## 📖 Documentação de Flows

Para qualquer feature ou fluxo, verifique a pasta `./docs/flow/`: leia os títulos dos arquivos `.md` disponíveis e, se algum for relevante para a tarefa atual, leia-o antes de implementar ou debugar. Invoque a skill `flow` para criar ou atualizar flows individuais.

## 🧪 Teste funcional

Após implementar, não execute o projeto para validar o resultado (rodar o app, emulador/simulador, dispositivo físico, servidor local, screenshots ou interação simulada). Teste funcional/visual é responsabilidade do usuário.

- Limite a verificação a análise estática, build/compile e testes automatizados
- Ao concluir, liste objetivamente o que o usuário deve testar manualmente
- Não pergunte se deve executar o projeto — só faça isso se o usuário pedir explicitamente

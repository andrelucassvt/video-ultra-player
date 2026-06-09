# video_ultra_player

Plugin Flutter federado (Dart + iOS/Swift + Android/Kotlin) para um player de timeline com composição nativa única (gapless real, CapCut-like). Hoje é skeleton de `flutter create --template=plugin` — só `getPlatformVersion` existe; a arquitetura-alvo está em `plan/`.

## Stack

- Dart `^3.11.5` / Flutter `>=3.3.0`; runtime dep: `plugin_platform_interface`
- iOS: Swift 5.0, deployment target 13.0, CocoaPods (`ios/video_ultra_player.podspec`)
- Android: Kotlin 2.2.20, Gradle **Kotlin DSL** (`build.gradle.kts`), `compileSdk 36`, `minSdk 24`, JVM 17
- Planejado: `androidx.media3` (`CompositionPlayer`) no Android e `AVFoundation` (`AVMutableComposition`) no iOS

## Arquitetura

Plugin federado: API pública Dart → platform interface (contrato abstrato) → method channel → implementação nativa por plataforma. A API nunca chama o channel direto; sempre passa por `VideoUltraPlayerPlatform.instance`.

```
VideoUltraPlayer → VideoUltraPlayerPlatform → MethodChannelVideoUltraPlayer
                                                 └→ iOS / Android (pluginClass)
```

## Estrutura

- `lib/video_ultra_player.dart` — API pública (consumida pelo app)
- `lib/video_ultra_player_platform_interface.dart` — contrato abstrato Dart↔nativo
- `lib/video_ultra_player_method_channel.dart` — implementação default via MethodChannel
- `ios/Classes/` — `FlutterPlugin` Swift
- `android/src/main/kotlin/com/andre/video_ultra_player/` — `FlutterPlugin` Kotlin
- `example/` — app que consome/demonstra o plugin
- `test/` — testes Dart (espelham `lib/`)
- `plan/` — arquitetura-alvo e plano de implementação (LEIA antes de implementar)
- `flow/` — documentação de fluxos (ver seção no fim)

## Comandos

- `flutter analyze` — lint/análise estática
- `flutter test` — testes unitários Dart
- `cd example && flutter run` — roda o app de exemplo em device/simulador
- `cd example && flutter run -d ios` / `-d android` — força a plataforma

## Convenções

- Nome do channel = nome do pacote (`video_ultra_player`); para a timeline, `video_ultra_player/timeline_player`. **Nunca** `com.luma_vid/...` (resíduo de outro contexto).
- Toda nova capacidade é federada: contrato em `platform_interface` → impl em `method_channel` → nativo iOS **e** Android. Não chame `MethodChannel` direto da API pública.
- Android é **Kotlin DSL** (`build.gradle.kts`) — edite `dependencies {}` em sintaxe Kotlin, não Groovy.
- Antes de criar/alterar features, a skill `brainstorming` é obrigatória (`.claude/rules/brainstorming.instructions.md`).
- Não criar arquivos `.md` para documentar mudanças de código.

## Gotchas

- O `CLAUDE.md` anterior descrevia uma arquitetura Clean Architecture de **app** (Cubits/GetIt/GoRouter) que **não existe** neste repo de plugin — foi descartada. Não recrie pastas `presentation/domain/data` aqui.
- Os arquivos do app consumidor citados nos planos (`SequencePreviewPlayer`, `VideoEditorService`, `TimelinePlaybackModel`) **vivem no app, não neste pacote** — não podem ser validados aqui.
- `AVPlayerLayer` (iOS) e `SurfaceView` (Android) **não são capturáveis** para textura; a timeline usa `AVPlayerItemVideoOutput.copyPixelBuffer` / `SurfaceTexture` do `TextureRegistry` (ver plano).

## Não fazer

- Não usar `print()` — use `log()` de `dart:developer`.
- Não rodar `flutter pub upgrade` sem perguntar.
- Não implementar a timeline em só uma plataforma sem alinhar — a paridade iOS/Android faz parte do contrato.

## 📖 Documentação de Flows

Para qualquer feature ou fluxo, verifique a pasta `./flow/`: leia os títulos dos arquivos `.md` disponíveis e, se algum for relevante para a tarefa atual, leia-o antes de implementar ou debugar. Use `/flow <nome>` para criar ou atualizar flows individuais.

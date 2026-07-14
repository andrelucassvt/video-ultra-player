# Estrutura do Projeto: video_ultra_player

> **Resumo:** Plugin Flutter federado (Dart + iOS/Swift + Android/Kotlin) para um player de timeline com composição nativa única (gapless real, CapCut-like). O código atual já expõe preview por `Texture`, exportação MP4, edição de clipes, thumbnails, trilha de áudio externa e um app de exemplo em formato de editor.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (API), Swift (iOS), Kotlin (Android) |
| Tipo de projeto | Flutter **plugin package** (federado, com `pluginClass`) |
| Gerenciador de pacotes | pub (Dart) · CocoaPods (iOS) · Gradle Kotlin DSL (Android) |
| SDK Dart | `^3.11.5` · Flutter `>=3.3.0` |
| iOS | deployment target `13.0`, Swift `5.0` |
| Android | `compileSdk 36`, `minSdk 24`, Java/JVM 17, Kotlin `2.2.20`, AGP `8.11.1` |
| Principais dependências | `plugin_platform_interface` (runtime) · `image_picker`/`file_picker` no example · Media3 no Android · AVFoundation no iOS |

## Arquitetura

O projeto segue o padrão de **plugin federado do Flutter**: a camada Dart fala com o nativo via *platform interface* + *method channel*, e cada plataforma (iOS/Android) tem sua própria implementação nativa registrada como `pluginClass`. A timeline usa `MethodChannel` para comandos, `EventChannel` para estado/progresso e `Texture` para renderizar a composição nativa.

```
Dart (lib/)
  VideoUltraPlayer / NativeTimelinePlayer (API pública)
    └─ VideoUltraPlayerPlatform  (platform interface — contrato abstrato)
          └─ MethodChannelVideoUltraPlayer  (implementação via MethodChannel)
                │  MethodChannel('video_ultra_player/timeline_player')
        ┌───────┴────────┐
   iOS (Swift)      Android (Kotlin)
   VideoUltraPlayerPlugin   VideoUltraPlayerPlugin
```

### Regras de dependência

- A API pública (`VideoUltraPlayer`) nunca chama o `MethodChannel` direto — sempre via `VideoUltraPlayerPlatform.instance`.
- Implementações de plataforma estendem `VideoUltraPlayerPlatform` e se registram via token (`plugin_platform_interface`).
- O channel legado de plataforma é `video_ultra_player`; a timeline usa `video_ultra_player/timeline_player`, **não** `com.luma_vid/...`.

## Features

| Feature | Caminho principal | Estado | Descrição resumida |
|---------|------------------|--------|-------------------|
| `getPlatformVersion` (boilerplate) | `lib/video_ultra_player.dart` + nativos | **Implementada** | Retorna a versão do SO; stub gerado pelo template de plugin |
| Native Timeline Player | `lib/src/native_timeline_player.dart` + nativos | **Implementada** | Composição nativa única (`AVMutableComposition` / Media3 `CompositionPlayer`) com `load/play/pause/seekTo/setVolume/setClipAlignment`, `stateStream`, imagens, export e edição |
| Clip speed | `TimelineClip.speed` + `setClipSpeed` | **Implementada** | Velocidade 0.5x–2.0x por clipe e export equivalente |
| Clip thumbnails | `generateThumbnails` + nativos | **Implementada** | Extração nativa de JPEGs cacheados para UI de timeline |
| Audio track | `AudioTrack` + `setAudioTrack/removeAudioTrack` | **Implementada** | Uma trilha de áudio externa com offset, volume, trim e fades |
| Undo/redo | `TimelineEditModel` iOS/Android | **Implementada** | Histórico nativo por snapshots de clipes + áudio |
| Editor example | `example/lib/editor/` | **Implementada** | UI escura com top bar, preview, timeline, áudio, playback bar e toolbar inferior |

## Camadas / Módulos

| Tipo | Caminho | Responsabilidade |
|------|---------|-----------------|
| API pública (Dart) | `lib/video_ultra_player.dart` | Superfície que o app consumidor usa; exporta models e `NativeTimelinePlayer` |
| API timeline (Dart) | `lib/src/native_timeline_player.dart` | Orquestra load/export/comandos, valida uso e expõe streams |
| Modelos Dart | `lib/src/models/` | Define clipes, config, progresso, estado, thumbnails, áudio e histórico |
| Platform interface | `lib/video_ultra_player_platform_interface.dart` | Contrato abstrato entre Dart e nativo |
| Method channel | `lib/video_ultra_player_method_channel.dart` | Implementação default via `MethodChannel`/`EventChannel` |
| iOS nativo | `ios/Classes/VideoUltraPlayerPlugin.swift` | Registra channels, gerencia controllers por textura, comandos e export |
| iOS composição | `ios/Classes/TimelineComposition.swift` | Monta `AVMutableComposition`, video composition, audio mix e segmentos |
| iOS textura | `ios/Classes/TimelineTexture.swift` | Entrega frames ao Flutter por `AVPlayerItemVideoOutput` |
| Android nativo | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | Registra channels, gerencia controllers por textura e exporters |
| Android composição | `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | Monta `CompositionPlayer`, `Transformer`, efeitos, estado e export |
| App de exemplo | `example/lib/main.dart` + `example/lib/editor/` | Demonstra o plugin em uma UI de editor de timeline |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|-----------------|
| Manifesto do pacote | `pubspec.yaml` | Nome, deps, `plugin.platforms` (`pluginClass`/`package`) |
| Podspec iOS | `ios/video_ultra_player.podspec` | Build iOS, deployment target, source files |
| Gradle Android | `android/build.gradle.kts` | `compileSdk`/`minSdk`, deps de teste, namespace e Media3 |
| Example pubspec | `example/pubspec.yaml` | App consumidor local, assets do demo, `image_picker` e `file_picker` |
| Lints | `analysis_options.yaml` | `flutter_lints` |

## Testes

| Camada | Arquivo | Cobre |
|--------|---------|-------|
| Dart (API/modelos) | `test/*_test.dart` | Models, API pública, validações, comandos, export e streams |
| Dart (channel) | `test/video_ultra_player_method_channel_test.dart` | Payloads do `MethodChannel` e parsing de estado |
| Android (unit) | `android/src/test/kotlin/.../VideoUltraPlayerPluginTest.kt` | JUnit + Mockito |
| iOS (unit) | `example/ios/RunnerTests/RunnerTests.swift` | XCTest |
| Exemplo (widget) | `example/test/widget_test.dart` | Renderização inicial do shell do editor |
| Integração | `example/integration_test/plugin_integration_test.dart` | Teste de integração end-to-end |

## Dependências Externas Principais

| Pacote / Biblioteca | Uso no projeto |
|--------------------|---------------|
| `plugin_platform_interface` | Base da platform interface federada (token de verificação) |
| `flutter_lints` | Regras de lint (dev) |
| `image_picker` | Seleção de vídeos no app de exemplo |
| `file_picker` | Seleção de áudio no app de exemplo |
| `androidx.media3` (`transformer`, `effect`, `common`) | Android: `CompositionPlayer`, efeitos e `Transformer` para preview/export |
| AVFoundation (iOS, framework do sistema) | `AVMutableComposition`, `AVPlayerItemVideoOutput`, áudio mix e export |

## Observações

- **Planos v2:** `plan/v2-00..v2-07` documentam a evolução recente; consulte antes de alterar capacidades ou UI do editor.
- **CLAUDE.md herdado:** o `CLAUDE.md` na raiz descrevia uma arquitetura Clean Architecture de **app** (Presentation/Domain/Data, Cubits, GetIt, GoRouter) que **não corresponde** a este repositório de plugin. Foi reescrito por esta skill para refletir a realidade de plugin federado.
- **Channel name:** há aviso recorrente nos planos para não usar `com.luma_vid/...` (resíduo de outro contexto) — os channels corretos são `video_ultra_player` e `video_ultra_player/timeline_player`.
- **Android usa Gradle Kotlin DSL** (`build.gradle.kts`), não `build.gradle` Groovy.

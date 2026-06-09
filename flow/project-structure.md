# Estrutura do Projeto: video_ultra_player

> **Resumo:** Plugin Flutter federado (Dart + iOS/Swift + Android/Kotlin) cujo objetivo é fornecer um player de timeline com composição nativa única (gapless real, CapCut-like). Hoje o repositório está no estado de skeleton (`flutter create --template=plugin`): a única capacidade implementada em todas as camadas é `getPlatformVersion`. A arquitetura-alvo está descrita em `plan/native-timeline-player-overview.md` e `plan/native-timeline-player-implementation.md`.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (API), Swift (iOS), Kotlin (Android) |
| Tipo de projeto | Flutter **plugin package** (federado, com `pluginClass`) |
| Gerenciador de pacotes | pub (Dart) · CocoaPods (iOS) · Gradle Kotlin DSL (Android) |
| SDK Dart | `^3.11.5` · Flutter `>=3.3.0` |
| iOS | deployment target `13.0`, Swift `5.0` |
| Android | `compileSdk 36`, `minSdk 24`, Java/JVM 17, Kotlin `2.2.20`, AGP `8.11.1` |
| Principais dependências | `plugin_platform_interface` (runtime) · `flutter_lints` (dev) |

## Arquitetura

O projeto segue o padrão de **plugin federado do Flutter**: a camada Dart fala com o nativo via *platform interface* + *method channel*, e cada plataforma (iOS/Android) tem sua própria implementação nativa registrada como `pluginClass`. A comunicação é por `MethodChannel` (comandos) e — na arquitetura-alvo — `EventChannel` (stream de estado) + `Texture` (render).

```
Dart (lib/)
  VideoUltraPlayer (API pública)
    └─ VideoUltraPlayerPlatform  (platform interface — contrato abstrato)
          └─ MethodChannelVideoUltraPlayer  (implementação via MethodChannel)
                │  MethodChannel('video_ultra_player')
        ┌───────┴────────┐
   iOS (Swift)      Android (Kotlin)
   VideoUltraPlayerPlugin   VideoUltraPlayerPlugin
```

### Regras de dependência

- A API pública (`VideoUltraPlayer`) nunca chama o `MethodChannel` direto — sempre via `VideoUltraPlayerPlatform.instance`.
- Implementações de plataforma estendem `VideoUltraPlayerPlatform` e se registram via token (`plugin_platform_interface`).
- O nome do channel deve ser o nome do pacote (`video_ultra_player`), **não** `com.luma_vid/...`.

## Features

O repositório está em estado de skeleton; a única capacidade implementada de ponta a ponta é a de boilerplate. A "feature" real do produto (timeline player) ainda não existe no código — está planejada.

| Feature | Caminho principal | Estado | Descrição resumida |
|---------|------------------|--------|-------------------|
| `getPlatformVersion` (boilerplate) | `lib/video_ultra_player.dart` + nativos | **Implementada** | Retorna a versão do SO; stub gerado pelo template de plugin |
| Native Timeline Player | `plan/native-timeline-player-implementation.md` | **Planejada** | Composição nativa única (`AVMutableComposition` / Media3 `CompositionPlayer`) → textura GPU única, gapless, com `load/play/pause/seekTo/setVolume/setClipAlignment`, `stateStream` e suporte a imagens |

## Camadas / Módulos

| Tipo | Caminho | Responsabilidade |
|------|---------|-----------------|
| API pública (Dart) | `lib/video_ultra_player.dart` | Superfície que o app consumidor usa |
| Platform interface | `lib/video_ultra_player_platform_interface.dart` | Contrato abstrato entre Dart e nativo |
| Method channel | `lib/video_ultra_player_method_channel.dart` | Implementação default via `MethodChannel('video_ultra_player')` |
| iOS nativo | `ios/Classes/VideoUltraPlayerPlugin.swift` | `FlutterPlugin` Swift; registra o channel |
| Android nativo | `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | `FlutterPlugin` Kotlin; registra o channel |
| App de exemplo | `example/lib/main.dart` | Demonstra/consome o plugin (hoje exibe a versão do SO) |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|-----------------|
| Manifesto do pacote | `pubspec.yaml` | Nome, deps, `plugin.platforms` (`pluginClass`/`package`) |
| Podspec iOS | `ios/video_ultra_player.podspec` | Build iOS, deployment target, source files |
| Gradle Android | `android/build.gradle.kts` | `compileSdk`/`minSdk`, deps de teste, namespace |
| Lints | `analysis_options.yaml` | `flutter_lints` |

## Testes

| Camada | Arquivo | Cobre |
|--------|---------|-------|
| Dart (API) | `test/video_ultra_player_test.dart` | Mock do platform interface; testa `getPlatformVersion` |
| Dart (channel) | `test/video_ultra_player_method_channel_test.dart` | `MethodChannel` mockado |
| Android (unit) | `android/src/test/kotlin/.../VideoUltraPlayerPluginTest.kt` | JUnit + Mockito |
| iOS (unit) | `example/ios/RunnerTests/RunnerTests.swift` | XCTest |
| Exemplo (widget) | `example/test/widget_test.dart` | Widget test do app de exemplo |
| Integração | `example/integration_test/plugin_integration_test.dart` | Teste de integração end-to-end |

## Dependências Externas Principais

| Pacote / Biblioteca | Uso no projeto |
|--------------------|---------------|
| `plugin_platform_interface` | Base da platform interface federada (token de verificação) |
| `flutter_lints` | Regras de lint (dev) |
| **Planejadas** — `androidx.media3` (`transformer`, `effect`, `common`) | Android: `CompositionPlayer` para a timeline (a fixar no `build.gradle.kts`) |
| **Planejadas** — `AVFoundation` (iOS, framework do sistema) | `AVMutableComposition` + `AVPlayerItemVideoOutput` para a timeline |

## Observações

- **Skeleton vs. plano:** todo o código nativo/Dart ainda é boilerplate. A direção do produto vive em `plan/` — consulte antes de implementar.
- **CLAUDE.md herdado:** o `CLAUDE.md` na raiz descrevia uma arquitetura Clean Architecture de **app** (Presentation/Domain/Data, Cubits, GetIt, GoRouter) que **não corresponde** a este repositório de plugin. Foi reescrito por esta skill para refletir a realidade de plugin federado.
- **Channel name:** há aviso recorrente nos planos para não usar `com.luma_vid/...` (resíduo de outro contexto) — o channel deve ser `video_ultra_player`.
- **Android usa Gradle Kotlin DSL** (`build.gradle.kts`), não `build.gradle` Groovy.

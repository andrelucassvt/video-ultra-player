---
generated_at: 2026-07-31
source_commit: 1e11b62
source_state: clean
verified_at: 2026-07-31
status: current
related_plans:
  - docs/plan/onda-1-quick-wins.md
  - docs/plan/onda-2-identidade-editor.md
---

# Estrutura do Projeto: video_ultra_player

> **Resumo:** Plugin Flutter federado (Dart + iOS/Swift + Android/Kotlin) que compõe uma sequência de clipes em uma única composição nativa — preview gapless renderizado em `Texture` e export MP4 do mesmo estado editado.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (API pública), Swift (iOS), Kotlin (Android) |
| Tipo de projeto | Flutter **plugin package** federado (`flutter.plugin.platforms` em `pubspec.yaml`) |
| Versão do pacote | `2.0.5` (`pubspec.yaml`) |
| Gerenciador de pacotes | pub · CocoaPods (`ios/video_ultra_player.podspec`) · Gradle **Kotlin DSL** (`android/build.gradle.kts`) |
| SDK | Dart `^3.11.5`, Flutter `>=3.3.0` |
| iOS | Swift 5.0, deployment target 13.0, AVFoundation |
| Android | Kotlin 2.2.20, AGP 8.11.1, `compileSdk 36`, `minSdk 24`, JVM 17, `androidx.media3` 1.10.1 |
| Dependência runtime Dart | `plugin_platform_interface ^2.0.2` |
| Lint | `flutter_lints ^6.0.0` via `analysis_options.yaml` |

## Arquitetura

Plugin federado clássico: a API pública Dart delega para uma *platform interface* abstrata, cuja implementação default fala com o nativo por `MethodChannel` + dois `EventChannel`. Cada plataforma registra sua própria `pluginClass` e mantém um mapa `textureId → controller`, de modo que o `textureId` devolvido por `load` é a chave de todas as chamadas seguintes e também o id da `Texture` desenhada no Flutter.

O vídeo **não** usa `AVPlayerLayer` nem `SurfaceView`: no iOS os frames vêm de `AVPlayerItemVideoOutput.copyPixelBuffer` entregues ao `FlutterTextureRegistry`; no Android o `CompositionPlayer` desenha em um `Surface` criado sobre o `SurfaceTexture` do `TextureRegistry`.

Preview e export compartilham o mesmo estado nativo: `exportCurrentTimeline` reusa a lista de clipes já editada no controller, então o MP4 exportado corresponde ao que o preview mostra.

```
Dart (lib/)
  NativeTimelinePlayer                     (API pública, validações de argumento)
    └─ VideoUltraPlayerPlatform            (contrato abstrato — PlatformInterface)
         └─ MethodChannelVideoUltraPlayer  (serialização Map<String, Object?>)
              │ MethodChannel  video_ultra_player/timeline_player
              │ EventChannel   video_ultra_player/timeline_player/events   (estado)
              │ EventChannel   video_ultra_player/timeline_player/export   (progresso)
      ┌───────┴────────────────────────┐
 iOS (Swift)                     Android (Kotlin)
 VideoUltraPlayerPlugin          VideoUltraPlayerPlugin
   └─ TimelinePlayerController     └─ TimelineCompositionController
        ├─ TimelineComposition          (AVMutableComposition / Media3 Composition)
        ├─ TimelineTexture              (Surface + SurfaceTexture no Android)
        └─ TimelineEditModel            (pilhas undo/redo, limite 50)
```

### Regras de dependência

- A API pública nunca instancia `MethodChannel`: `NativeTimelinePlayer` recebe (ou resolve) um `VideoUltraPlayerPlatform` e chama só o contrato.
- Toda operação de player exige `textureId`; `generateThumbnails` é a única exceção — é utilitário standalone e não depende de `load`.
- Modelos ficam em `lib/src/models/` e só são expostos pelo barrel `lib/video_ultra_player.dart`; o nativo recebe/emite mapas planos em milissegundos.
- Qualquer capacidade nova precisa existir nas quatro camadas: platform interface → method channel → iOS → Android.

## Features

| Feature | Caminho principal | Descrição resumida |
|---------|------------------|-------------------|
| Timeline player | `lib/src/native_timeline_player.dart` | Carrega clipes, controla playback, expõe `stateStream` e `textureId` |
| Camada nativa iOS | `ios/Classes/` | `AVMutableComposition` + `AVPlayer` + `AVPlayerItemVideoOutput` |
| Camada nativa Android | `android/src/main/kotlin/com/andre/video_ultra_player/` | Media3 `CompositionPlayer` + `Transformer` |
| Edição de clipes | `TimelineComposition.swift` / `TimelineCompositionController.kt` | trim, split, insert, remove, move, replace, speed, alignment |
| Undo / redo | `ios/Classes/TimelineEditModel.swift`, `.../TimelineEditModel.kt` | Pilhas de snapshot (clipes + trilha de áudio), limite 50 |
| Export MP4 | `VideoUltraPlayerPlugin.swift`, `TimelineCompositionExporter` (Kotlin) | `AVAssetExportSession` / `Transformer` com progresso por evento |
| Trilha de áudio externa | `lib/src/models/audio_track.dart` + nativo | Overlay com offset, volume, trim e fades |
| Thumbnails | `ios/Classes/ThumbnailGenerator.swift`, `.../ThumbnailGenerator.kt` | Extração de frames JPEG em cache de disco |
| App de exemplo (editor) | `example/lib/editor/` | Editor CapCut-like que consome o plugin |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|-----------------|
| Modelos Dart | `lib/src/models/` | `TimelineClip`, `AudioTrack`, `TimelineCompositionConfig`, `TimelinePlayerState`, `TimelineExportProgress`, `ClipTransition`, `ClipThumbnail`, `EditHistoryState` |
| Contrato Dart↔nativo | `lib/video_ultra_player_platform_interface.dart` | Assinaturas abstratas de todas as operações |
| Serialização de channel | `lib/video_ultra_player_method_channel.dart` | Nomes de método, chaves dos mapas, decodificação dos eventos |
| Descritores nativos | `TimelineComposition.swift` (structs), `TimelineCompositionController.kt` (data classes) | Espelham os modelos Dart no lado nativo (`TimelineClipDescriptor`, `AudioTrackDescriptor`, `TimelineCompositionConfig`) |
| Tema do exemplo | `example/lib/editor/theme/editor_theme.dart` | Paleta escura e `ThemeData` do editor |
| Widgets do exemplo | `example/lib/editor/widgets/` | Preview, régua, playhead, faixa de clipes, handles de trim, toolbars, sheets |
| Testes Dart | `test/` | Modelos, `NativeTimelinePlayer` (platform fake) e `MethodChannelVideoUltraPlayer` |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|-----------------|
| Registro do plugin | `pubspec.yaml` (`flutter.plugin.platforms`) | `package: com.andre.video_ultra_player`, `pluginClass: VideoUltraPlayerPlugin` nas duas plataformas |
| Build Android | `android/build.gradle.kts` | Media3, JVM 17, `srcDirs("src/main/kotlin")`, JUnit Platform nos testes |
| Build iOS | `ios/video_ultra_player.podspec` | `s.source_files = 'Classes/**/*'`, `platform :ios, '13.0'` |
| Entrypoint do exemplo | `example/lib/main.dart` | `TimelineEditorApp` → `EditorScreen(autoLoad: true)` |
| Estado do exemplo | `example/lib/editor/editor_controller.dart` | `ChangeNotifier` que orquestra o plugin, seek throttling e undo/redo local |
| Sincronização de instruções | `sync-instructions.sh`, `sync-brain.sh` | Copiam skills/agentes do repositório central para `.claude/`, `.agents/`, `.github/` |

## Dependências Externas Principais

| Pacote | Versão | Uso no projeto |
|--------|--------|---------------|
| `plugin_platform_interface` | ^2.0.2 | Token de verificação da platform interface |
| `androidx.media3:media3-transformer` | 1.10.1 | `CompositionPlayer` (preview) e `Transformer` (export) |
| `androidx.media3:media3-effect` | 1.10.1 | `Presentation` e `Crop` por clipe |
| `androidx.media3:media3-common` | 1.10.1 | `MediaItem`, `GainProcessor`, `SpeedProvider` |
| AVFoundation / UIKit | SDK iOS | Composição, export, geração de vídeo a partir de imagem, thumbnails |
| `image_picker` / `file_picker` / `gal` | ^1.2.2 / ^11.0.2 / ^2.3.1 | Só no `example/`: escolher clipes, escolher áudio, salvar export na galeria |

## Observações

- **`podspec` desalinhado:** `ios/video_ultra_player.podspec` declara `s.version = '1.1.0'` enquanto `pubspec.yaml` está em `2.0.5`.
- **Transição declarada mas não aplicada:** `ClipTransition`/`TransitionType.crossfade` é serializado e lido pelos dois nativos (`transitionToNextMs`), porém nenhuma plataforma usa o valor para compor um crossfade — o split apenas o zera. Na prática todo limite entre clipes é corte seco.
- **Modelos sem caminho ativo:** `ClipThumbnail` e `EditHistoryState` existem e têm teste, mas o channel não os produz — `generateThumbnails` devolve `List<String>` e `canUndo`/`canRedo` chegam dentro de `TimelinePlayerState`.
- **Log de diagnóstico em produção:** `ios/Classes/TimelineTexture.swift` mantém `NSLog` marcado como "remove when fixed" até capturar o primeiro frame.
- **I/O na main thread (Android):** `resolveClip` usa `MediaMetadataRetriever` de forma síncrona dentro de `load`, `insertClip` e `replaceClip`, que rodam na thread do channel.
- **Instruções antigas obsoletas:** `AGENTS.md`/`CLAUDE.md` anteriores descreviam o repo como skeleton com `getPlatformVersion` e apontavam para `plan/` e `flow/`; nada disso existe — o método foi removido e a documentação vive em `docs/plan/` e `docs/flow/`.
- Não há teste automatizado das camadas nativas além de `android/src/test/.../VideoUltraPlayerPluginTest.kt`, que cobre apenas o caso `notImplemented()`.

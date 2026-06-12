# V2-03 — Trilha de Áudio (música / narração)

> **Objetivo:** Adicionar uma trilha de áudio única sobreposta à timeline (música/narração), com `offset`, `volume`, `trim` e `fade in/out`, refletida no preview e no export, de forma federada.

## Contexto

O wireframe (#6) mostra "Adicionar áudio — trilha de música / narração abaixo dos clipes". Hoje só existe áudio embutido em cada clipe de vídeo (`setVolume` global). **Decisão (overview #2):** **uma** trilha de áudio única na v2 (não múltiplas), com início na timeline (`offset`), `volume`, `trim` (in/out do arquivo) e `fade in/out` opcionais. Deve mixar com o áudio dos clipes e ser incluída no export.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `lib/src/models/audio_track.dart` | criar | `AudioTrack { String path; Duration offset; Duration? trimStart/trimEnd; double volume; Duration? fadeIn/fadeOut; }` + `toJson`/`copyWith`/`==` |
| `lib/video_ultra_player_platform_interface.dart` | editar | `setAudioTrack(int textureId, Map? track)` (null remove), `removeAudioTrack(int textureId)` |
| `lib/video_ultra_player_method_channel.dart` | editar | Implementar ambos via `invokeMethod` |
| `lib/src/native_timeline_player.dart` | editar | `setAudioTrack(AudioTrack track)` / `removeAudioTrack()` com `_requireTextureId` |
| `ios/Classes/TimelineComposition.swift` | editar | Adicionar uma `AVMutableCompositionTrack` de áudio para a trilha externa; inserir no `offset`; `AVMutableAudioMixInputParameters` com `volume` + ramps de fade |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | Dispatch `setAudioTrack`/`removeAudioTrack`; reconstrói/atualiza áudio mantendo textura e posição |
| `android/.../TimelineCompositionController.kt` | editar | Trilha de áudio como sequência Media3 paralela (ou `EditedMediaItem` de áudio) com offset/volume/fade; incluir no `Composition` de preview e export |
| `android/.../VideoUltraPlayerPlugin.kt` | editar | Dispatch dos métodos |
| `test/audio_track_test.dart` | criar | Serialização |
| `test/native_timeline_player_test.dart` | editar | `setAudioTrack`/`removeAudioTrack` delegam; exige load |
| `test/video_ultra_player_method_channel_test.dart` | editar | Payloads |

**Nota de fluidez (Android):** alterar a trilha reconstrói o `Composition` (Media3 imutável) — aplicar **no commit** do controle (ex: ao soltar o slider de volume), com debounce. iOS atualiza o `AVAudioMix` sem recriar o player quando possível.

## Fases

### Fase 1 — Testes (contrato)

- [x] `test/audio_track_test.dart`: `toJson` com `path/offsetMs/volume`, opcionais `trimStartMs/trimEndMs/fadeInMs/fadeOutMs`; `volume` clamp [0,1].
- [x] `test/native_timeline_player_test.dart`: `setAudioTrack` antes de `load` lança `StateError`; após load delega com JSON; `removeAudioTrack` envia `track: null` (ou método próprio).
- [x] `test/video_ultra_player_method_channel_test.dart`: payloads de `setAudioTrack`/`removeAudioTrack`.
- [x] Verificação: falham por método ausente.

### Fase 2 — Contrato Dart

- [x] Criar `AudioTrack`; exportar em `lib/video_ultra_player.dart`.
- [x] Adicionar métodos ao platform interface + method channel + `NativeTimelinePlayer`.
- [x] Verificação: `flutter test`/`flutter analyze` verdes.

### Fase 3 — Nativo iOS

- [x] `TimelineComposition`: track de áudio externa inserida em `offset`; respeitar `trimStart/trimEnd`; `AVMutableAudioMixInputParameters` com `setVolume` + `setVolumeRamp` para fade in/out; mixar com áudio dos clipes.
- [x] Plugin: `setAudioTrack` atualiza o `AVAudioMix` (e a composição se necessário) mantendo `textureId`/posição; `removeAudioTrack` remove a track.
- [x] Garantir que `buildExportAsset` inclua a trilha externa (mesmo `AVAudioMix`).
- [ ] Verificação: música toca a partir do offset, com volume/fade; export contém a trilha.

### Fase 4 — Nativo Android

- [x] `TimelineCompositionController`: trilha de áudio externa como sequência paralela na `Composition` (ou `EditedMediaItem` de áudio com `setEffects` de volume/fade); aplicar `offset` via posicionamento; trim via `ClippingConfiguration`.
- [x] Plugin: dispatch; `setComposition(...)` apenas no commit; export (`Transformer`) inclui a trilha.
- [ ] Verificação: paridade com iOS no preview e no export.

## Critérios de Sucesso

- [ ] Uma trilha de áudio externa toca sobre os clipes a partir do `offset`, com `volume`, `trim` e `fade`.
- [x] Export inclui a trilha mixada.
- [x] Remover a trilha volta ao áudio só dos clipes.
- [x] `flutter test`/`flutter analyze` verdes.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Mixagem Media3 da trilha paralela no preview | Alta | Validar `CompositionPlayer` com 2 sequências (vídeo+áudio); se limitado, mixar via `EditedMediaItem` de áudio numa sequência dedicada |
| Sincronismo offset entre preview e export | Média | Reusar mesmo builder de composição para preview e `Transformer`; teste manual de sincronismo |
| Fade ramps divergentes iOS/Android | Baixa | Definir curva linear como contrato; documentar |

## Rollback

Aditivo; remover models/métodos e a track externa da composição. Sem trilha, comportamento atual (áudio só dos clipes) permanece.

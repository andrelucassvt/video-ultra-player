# Onda 1 — Quick Wins da API do Timeline Player

> **Objetivo:** Entregar seis capacidades que fecham as lacunas mais visíveis da API atual — cancelar exportação, volume/mute por clipe, probe de metadata, rotação/espelhamento de clipe, loop + intervalo A–B de playback e snapshot do frame atual — com paridade iOS/Android.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/native-timeline-player.md`, `docs/flow/ios-native-layer.md`, `docs/flow/android-implementation.md`, `docs/flow/project-structure.md`

## Contexto

O plugin já tem timeline gapless com edição (trim/split/insert/remove/move/replace), undo/redo nativo, transição crossfade, trilha de áudio externa e export com progresso real. Porém a API expõe apenas volume global, não há como cancelar um export em andamento, o app consumidor precisa adivinhar metadata dos arquivos, não há rotação de clipe, o preview não faz loop nem restringe intervalo, e não é possível capturar o frame atual. São seis lacunas pequenas e independentes entre si.

## Design de Origem

- **Decisão aprovada:** Implementar os seis quick wins como extensões do contrato federado existente (platform interface → method channel → iOS e Android juntos), sem mudanças estruturais: novos campos em `TimelineClip` (volume/mute, rotação/flip), um novo modelo `MediaInfo`, e novos métodos no `NativeTimelinePlayer`.
- **Alternativas descartadas:** Implementar loop/A–B no lado Dart (ouvindo `stateStream` e re-seekando) — descartado porque o seek de retorno via channel tem latência perceptível; o loop nativo é frame-accurate. Snapshot via re-export de 1 frame — descartado por custo; o pipeline de pixel buffer do preview já tem o frame em mãos.
- **Tipo de mudança:** Logic

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models/media_info.dart` | criar | Modelo `MediaInfo` (duração, largura, altura, fps, rotação, hasAudio) + `fromJson` |
| `lib/src/models/timeline_clip.dart` | editar | Novos campos: `volume` (0.0–1.0, default 1.0), `muted` (bool), `rotation` (enum 0/90/180/270), `flipHorizontal`, `flipVertical` — serialização em `toJson`/`copyWith` |
| `lib/video_ultra_player_platform_interface.dart` | editar | Novos métodos abstratos: `cancelExport`, `getMediaInfo`, `setClipVolume`, `setClipRotation`, `setLooping`, `setPlaybackRange`, `clearPlaybackRange`, `captureFrame` |
| `lib/video_ultra_player_method_channel.dart` | editar | Implementação via `MethodChannel` dos oito métodos novos |
| `lib/src/native_timeline_player.dart` | editar | API pública com validações (volume 0–1, range start < end) |
| `lib/video_ultra_player.dart` | editar | Exportar `MediaInfo` e novos enums |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | Roteamento dos oito comandos novos no MethodChannel |
| `ios/Classes/TimelineComposition.swift` | editar | Audio mix por clipe, transform de rotação/flip, loop/A–B via boundary observer, `cancelExport` na export session |
| `ios/Classes/TimelineTexture.swift` | editar | `captureFrame`: último `CVPixelBuffer` → PNG em arquivo temporário |
| `ios/Classes/TimelineEditModel.swift` | editar | Incluir volume/mute/rotação nos snapshots de undo/redo |
| `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | editar | Roteamento dos oito comandos novos |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | editar | Volume por `EditedMediaItem`, `ScaleAndRotateTransformation`, loop/A–B via listener de posição, `cancelExport` no `Transformer`, captura de frame do pipeline GL, `getMediaInfo` via `MediaMetadataRetriever` |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt` | editar | Incluir novos atributos nos snapshots de undo/redo |
| `test/media_info_test.dart` | criar | Testes de desserialização do `MediaInfo` |
| `test/timeline_clip_test.dart` | editar | Testes dos novos campos e serialização |
| `test/native_timeline_player_test.dart` | editar | Testes das novas APIs (validações + delegação à platform) |
| `test/video_ultra_player_method_channel_test.dart` | editar | Testes dos novos method calls (nome do método + argumentos) |
| `example/lib/editor/editor_controller.dart` | editar | Ações de volume, rotação, loop, snapshot e cancelar export |
| `example/lib/editor/editor_screen.dart` | editar | Controles de UI para as novas ações |

## Fases

### Fase 1 — Testes dos modelos Dart (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Criar `test/media_info_test.dart`: `MediaInfo.fromJson` com mapa completo, com campos ausentes (fps/rotação opcionais) e com `hasAudio` false
- [ ] Em `test/timeline_clip_test.dart`: cobrir `volume`/`muted`/`rotation`/`flipHorizontal`/`flipVertical` em construtor, `toJson`, `copyWith` e defaults (volume 1.0, muted false, rotation 0, flips false)
- [ ] Em `test/timeline_clip_test.dart`: `volume` fora de [0.0, 1.0] lança `ArgumentError`
- [ ] Verificação: `flutter test test/media_info_test.dart test/timeline_clip_test.dart` compila e falha pelos motivos certos

### Fase 2 — Implementação dos modelos Dart

- [ ] Criar `lib/src/models/media_info.dart` com `MediaInfo` imutável + `fromJson`
- [ ] Adicionar em `lib/src/models/timeline_clip.dart` os campos `volume`, `muted`, `rotation` (enum `ClipRotation { r0, r90, r180, r270 }`), `flipHorizontal`, `flipVertical` com validação e serialização
- [ ] Exportar `MediaInfo` e `ClipRotation` em `lib/video_ultra_player.dart`
- [ ] Verificação: testes da Fase 1 passam; `flutter analyze` limpo

### Fase 3 — Testes do contrato platform/channel

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Em `test/video_ultra_player_method_channel_test.dart`: verificar nome do método e argumentos serializados de `cancelExport`, `getMediaInfo`, `setClipVolume`, `setClipRotation`, `setLooping`, `setPlaybackRange`, `clearPlaybackRange`, `captureFrame`
- [ ] Em `test/native_timeline_player_test.dart`: `setClipVolume` rejeita volume fora de [0,1]; `setPlaybackRange` rejeita `start >= end`; `captureFrame` exige `load` prévio; `cancelExport` é no-op seguro sem export ativo
- [ ] Verificação: testes compilam e falham pelos motivos certos

### Fase 4 — Implementação do contrato Dart

- [ ] Adicionar os oito métodos abstratos em `lib/video_ultra_player_platform_interface.dart` (com `UnimplementedError` default)
- [ ] Implementar em `lib/video_ultra_player_method_channel.dart` os oito method calls no channel `video_ultra_player/timeline_player`
- [ ] Adicionar API pública em `lib/src/native_timeline_player.dart`: `cancelExport()`, `getMediaInfo(path)` (estático/utilitário como `generateThumbnails`), `setClipVolume(clipIndex, volume)`, `setClipRotation(clipIndex, rotation, {flipHorizontal, flipVertical})`, `setLooping(bool)`, `setPlaybackRange(Duration start, Duration end)`, `clearPlaybackRange()`, `captureFrame()` → path do PNG
- [ ] Verificação: testes das Fases 1 e 3 passam; `flutter analyze` limpo

### Fase 5 — iOS: export cancelável, metadata e volume por clipe

- [ ] `TimelineComposition.swift`: guardar referência da export session ativa e implementar `cancelExport` (cancela e responde o call de export pendente com erro `export_cancelled`)
- [ ] `VideoUltraPlayerPlugin.swift`: comando `getMediaInfo` via `AVURLAsset` (`load(.duration, .tracks)`) retornando duração ms, largura/altura (com `preferredTransform` aplicado), fps nominal, rotação e `hasAudio`
- [ ] `TimelineComposition.swift`: aplicar `AVMutableAudioMixInputParameters` por segmento de clipe usando `volume`/`muted` do clipe (mute = 0.0), tanto no preview quanto no export
- [ ] `TimelineEditModel.swift`: incluir volume/mute nos snapshots de undo/redo
- [ ] Verificação: `cd example/ios && pod install` sem erro e build Swift compila (`xcodebuild build` do exemplo, sem rodar app)

### Fase 6 — iOS: rotação, loop/A–B e snapshot

- [ ] `TimelineComposition.swift`: aplicar rotação (0/90/180/270) + flips como `CGAffineTransform` na instrução de composição do clipe, ajustando o render size do canvas quando 90/270
- [ ] `TimelineComposition.swift`: `setLooping` e `setPlaybackRange` via boundary time observer — ao alcançar o fim do range (ou da timeline com loop ativo), seek frame-accurate para o início do range
- [ ] `TimelineTexture.swift`: `captureFrame` converte o último `CVPixelBuffer` servido à textura em PNG (via `CIContext`) salvo em diretório temporário; retornar o path
- [ ] `TimelineEditModel.swift`: incluir rotação/flips nos snapshots
- [ ] Verificação: build Swift do exemplo compila

### Fase 7 — Android: export cancelável, metadata e volume por clipe

- [ ] `TimelineCompositionController.kt`: implementar `cancelExport` chamando `Transformer.cancel()` e respondendo o result pendente com erro `export_cancelled`
- [ ] `VideoUltraPlayerPlugin.kt`: comando `getMediaInfo` via `MediaMetadataRetriever` (duração, largura/altura, rotação, fps via `METADATA_KEY_CAPTURE_FRAMERATE`/track, `hasAudio`)
- [ ] `TimelineCompositionController.kt`: volume/mute por clipe via `ChannelMixingAudioProcessor` com matriz de ganho no `Effects` do `EditedMediaItem` (preview e export)
- [ ] `TimelineEditModel.kt`: incluir volume/mute nos snapshots de undo/redo
- [ ] Verificação: `cd example && flutter build apk --debug` compila (sem rodar app)

### Fase 8 — Android: rotação, loop/A–B e snapshot

- [ ] `TimelineCompositionController.kt`: rotação/flips via `ScaleAndRotateTransformation` (rotação) e `MatrixTransformation` de espelhamento no `Effects` do clipe
- [ ] `TimelineCompositionController.kt`: `setLooping`/`setPlaybackRange` — listener de posição do `CompositionPlayer` que faz `seekTo(rangeStart)` ao cruzar `rangeEnd` (ou fim da timeline com loop)
- [ ] `TimelineCompositionController.kt`: `captureFrame` — ler o frame corrente do pipeline GL da `SurfaceTexture` (`glReadPixels` no contexto GL existente) → `Bitmap` → PNG em cache dir; retornar path
- [ ] `TimelineEditModel.kt`: incluir rotação/flips nos snapshots
- [ ] Verificação: `flutter build apk --debug` do exemplo compila

### Fase 9 — App de exemplo e documentação

- [ ] `example/lib/editor/editor_controller.dart`: ações de volume por clipe, rotação 90°, toggle de loop, snapshot e botão de cancelar durante export
- [ ] `example/lib/editor/editor_screen.dart`: controles ligados às novas ações (slider de volume no clipe selecionado, botão girar, toggle loop, botão snapshot, botão cancelar no diálogo de progresso)
- [ ] Atualizar `CHANGELOG.md` e a versão em `pubspec.yaml`
- [ ] Verificação: `flutter analyze` limpo no pacote e no `example`; `flutter test` completo passa

### Fase 10 — Atualizar Flows

- [ ] `docs/flow/native-timeline-player.md`: adicionar os oito métodos novos à lista de comandos, os novos campos de `TimelineClip` e o modelo `MediaInfo`
- [ ] `docs/flow/ios-native-layer.md`: atualizar contagem/tabela de comandos do MethodChannel e descrever audio mix por clipe, loop/A–B e captura de frame
- [ ] `docs/flow/android-implementation.md`: idem para o lado Android (ChannelMixingAudioProcessor, ScaleAndRotateTransformation, cancel do Transformer)
- [ ] Verificação: resumos (`> **Resumo:**`) dos três flows continuam fiéis ao conteúdo

## Critérios de Sucesso

- [ ] Os oito métodos novos existem nas três camadas Dart e nas duas plataformas nativas
- [ ] `TimelineClip` serializa volume/mute/rotação/flips e o undo/redo preserva esses atributos
- [ ] Export em andamento pode ser cancelado sem crash e o future pendente termina com erro identificável
- [ ] Build sem erros (analyze + `flutter build apk --debug` + build iOS do exemplo)
- [ ] Todos os testes unitários passando
- [ ] _(manual — feito pelo usuário)_ Validação funcional no app de exemplo (girar clipe, mutar clipe, loop A–B, snapshot, cancelar export)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `captureFrame` no Android exigir mudanças no pipeline GL da textura (contexto não acessível no momento da captura) | Média | Fallback: capturar o próximo frame no callback `onFrameAvailable` (latência de 1 frame); se inviável, degradar para thumbnail do clipe corrente na posição atual e registrar a limitação |
| Loop/A–B via listener de posição no Android ter jitter no ponto de volta | Média | Usar tick curto (~50 ms) já existente do emissor de estado e seek com `SeekParameters` exatos; aceitar jitter ≤ 1 frame |
| Rotação 90/270 interagir mal com o pan/crop (`setClipAlignment`) existente | Média | Aplicar rotação antes do crop na cadeia de transforms e cobrir o caso no teste manual; documentar a ordem no flow |
| `ChannelMixingAudioProcessor` não aplicar ganho como esperado em stream mono | Baixa | Testar matriz mono→mono e estéreo→estéreo; alternativa: baixar volume via `SonicAudioProcessor`/gain no mixer |

## Rollback

Reverter o(s) commit(s) da onda — as mudanças são aditivas ao contrato (nenhum método existente muda de assinatura), então o rollback não quebra consumidores existentes.

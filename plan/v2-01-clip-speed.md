# V2-01 — Velocidade do Clipe (0.5× – 2×)

> **Objetivo:** Permitir ajustar a velocidade de reprodução de um clipe de vídeo entre 0.5× e 2×, refletido no preview nativo e no export, de forma federada (iOS + Android).

## Contexto

O wireframe (#8) exige acelerar/desacelerar um clipe selecionado entre 0.5× e 2×. Hoje não existe nenhuma API de velocidade. A capacidade é federada e altera duração efetiva do clipe (afeta `clipDurations`/`totalDuration` e a régua da timeline). Primeiro plano de capacidade da v2 porque é o de menor superfície e estabelece o padrão para os demais.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `lib/src/models/timeline_clip.dart` | editar | Adicionar campo `double speed` (default 1.0, range [0.5, 2.0], assert), serializar `speed` em `toJson`, incluir em `copyWith`/`==`/`hashCode` |
| `lib/video_ultra_player_platform_interface.dart` | editar | Adicionar `Future<void> setClipSpeed(int textureId, int clipIndex, double speed)` |
| `lib/video_ultra_player_method_channel.dart` | editar | Implementar `setClipSpeed` → `invokeMethod('setClipSpeed', {textureId, clipIndex, speed})` |
| `lib/src/native_timeline_player.dart` | editar | Método público `setClipSpeed(int clipIndex, double speed)` com validação de range e `clipIndex >= 0` |
| `ios/Classes/TimelineComposition.swift` | editar | Aplicar `scaleTimeRange(_:toDuration:)` na track de vídeo+áudio do segmento ao montar; recalcular `TimelineSegment` e duração total com a velocidade |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | Dispatch de `setClipSpeed` → controller; reaplica composição mantendo posição/textura |
| `android/.../TimelineCompositionController.kt` | editar | Aplicar `SpeedChangeEffect`/`setSpeedProvider` (Media3) ou `Effects` de velocidade no `EditedMediaItem`; recalcular `durationUs`/segmentos |
| `android/.../VideoUltraPlayerPlugin.kt` | editar | Dispatch de `setClipSpeed` |
| `test/timeline_clip_test.dart` | editar | Serialização de `speed` |
| `test/native_timeline_player_test.dart` | editar | `setClipSpeed` valida range, delega à plataforma |
| `test/video_ultra_player_method_channel_test.dart` | editar | Payload de `setClipSpeed` |

**Nota de fluidez (Android):** `setClipSpeed` reconstrói a `Composition` (efeitos Media3 imutáveis) — chamar **apenas no release** do controle de velocidade, nunca por tick. iOS reaplica via `scaleTimeRange` na recomposição; também só no commit.

## Fases

### Fase 1 — Testes (contrato antes da implementação)

- [x] `test/timeline_clip_test.dart`: `toJson` inclui `'speed'`; default 1.0; assert lança fora de `[0.5, 2.0]`.
- [x] `test/native_timeline_player_test.dart`: `setClipSpeed(0, 1.5)` chama `platform.setClipSpeed(textureId, 0, 1.5)`; `setClipSpeed(-1, ...)` lança `ArgumentError`; `speed < 0.5` ou `> 2.0` lança `RangeError`.
- [x] `test/video_ultra_player_method_channel_test.dart`: `setClipSpeed` envia `{'textureId', 'clipIndex', 'speed'}`.
- [x] Verificação: testes compilam e falham por método ausente (não por sintaxe).

### Fase 2 — Contrato Dart (fazer testes Dart passarem)

- [x] Adicionar `speed` em `TimelineClip` (campo, assert `0.5 <= speed <= 2.0`, `toJson`, `copyWith`, `==`, `hashCode`).
- [x] Adicionar `setClipSpeed` ao `VideoUltraPlayerPlatform` (UnimplementedError default).
- [x] Implementar em `MethodChannelVideoUltraPlayer`.
- [x] Implementar `NativeTimelinePlayer.setClipSpeed` com validações.
- [x] Verificação: `flutter test` verde; `flutter analyze` limpo.

### Fase 3 — Nativo iOS

- [x] Em `TimelineComposition`: ao inserir o segmento de vídeo, aplicar `scaleTimeRange(originalRange, toDuration: original/speed)` nas tracks de vídeo e áudio; propagar a duração escalada para `TimelineSegment` e `totalDuration`.
- [x] `VideoUltraPlayerPlugin.swift`: tratar `setClipSpeed` buscando controller por `textureId`, atualizar o descriptor do clipe e reconstruir a composição mantendo `currentTime` e `textureId`.
- [ ] Verificação: clipe a 2× dura metade; `seekToClip` e estado refletem a nova duração.

### Fase 4 — Nativo Android

- [x] Em `buildTimelineComposition`: aplicar `Effects.createExperimentalSpeedChangingEffect(SpeedProvider)` (audio+video sincronizados) no `EditedMediaItem` do clipe; ajustar segmentos com `scaledDurationMs` para a duração escalada.
- [x] `VideoUltraPlayerPlugin.kt`: dispatch de `setClipSpeed`; `setComposition(buildTimelineComposition(clips), positionMs)` **apenas no commit**.
- [ ] Verificação: paridade com iOS (duração e estado corretos); export reflete a velocidade.

## Critérios de Sucesso

- [ ] Clipe selecionado pode ir de 0.5× a 2×; preview e export refletem.
- [ ] `clipDurations`/`totalDuration` no `stateStream` consideram a velocidade.
- [x] Sem rebuild por tick (Android aplica no release).
- [x] `flutter test` e `flutter analyze` verdes.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Áudio fica "chipmunk" em velocidade alta | Média | Aceitar pitch alterado na v2 (CapCut default) ou aplicar pitch-correction nativa se trivial; documentar |
| Media3 `SpeedChangeEffect` indisponível na versão atual | Média | Verificar API na media3 1.10.1; fallback para `setSpeed` no provider de transformação |
| Recalcular duração quebra `seekToClip`/segmentos | Média | Cobrir com teste de estado; recomputar segmentos a partir da duração escalada |

## Rollback

Reverter os campos/métodos adicionados; `speed` é aditivo (default 1.0) — remover não afeta clipes existentes.

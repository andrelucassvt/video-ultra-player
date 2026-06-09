# Native Timeline Player — Plano de Implementação

> **Objetivo:** Transformar o skeleton atual de plugin (`getPlatformVersion`) em um player de timeline com composição nativa única (`AVMutableComposition` no iOS / Media3 `CompositionPlayer` no Android), renderizando para uma textura GPU única (gapless real), exposto por uma API Dart (`NativeTimelinePlayer`), e demonstrado em `example/`.

## Contexto

O pacote `video_ultra_player` (`com.andre.video_ultra_player`) está hoje como skeleton de `flutter create --template=plugin`: Dart, iOS (`ios/Classes/VideoUltraPlayerPlugin.swift`) e Android (`android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt`) só implementam `getPlatformVersion`. A motivação está em `plan/native-timeline-player-overview.md`: `video_player` usa um `AVPlayer`/`ExoPlayer` por clipe e o swap de texturas causa flash/gap no boundary. A meta é uma composição única (CapCut-like) com um único decoder + uma única textura. Este plano materializa o overview em fases acionáveis e termina implementando um demo real em `example/`.

> ⚠️ O channel deve usar o nome do pacote (`video_ultra_player`), **não** `com.luma_vid/...` (resíduo de outro contexto). Os arquivos do app consumidor citados no overview (`SequencePreviewPlayer`, `VideoEditorService`, `TimelinePlaybackModel`) **não vivem neste repositório** — não serão tocados aqui.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models/timeline_clip.dart` | criar | `TimelineClip` + `MediaType` (path, type, duration, alignment, scale) + `toJson()` |
| `lib/src/models/timeline_player_state.dart` | criar | `TimelinePlayerState` (globalPosition, clipIndex, localPosition, isPlaying, totalDuration) + `fromMap()` |
| `lib/src/native_timeline_player.dart` | criar | API pública: `load/play/pause/seekTo/setVolume/setClipAlignment/dispose`, `stateStream`, `textureId` |
| `lib/video_ultra_player_platform_interface.dart` | editar | substituir `getPlatformVersion` pelos contratos da timeline |
| `lib/video_ultra_player_method_channel.dart` | editar | implementar via `MethodChannel('video_ultra_player/timeline_player')` + `EventChannel('.../events')` |
| `lib/video_ultra_player.dart` | editar | re-exportar `NativeTimelinePlayer`, `TimelineClip`, `MediaType`, `TimelinePlayerState` |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | reescrever | registrar channels, criar `AVMutableComposition`, `FlutterTexture`, observers |
| `ios/Classes/TimelineComposition.swift` | criar | montagem da composição + `AVVideoComposition` (transform/scale/crop por segmento) |
| `ios/Classes/TimelineTexture.swift` | criar | `AVPlayerItemVideoOutput` + `CADisplayLink` → `FlutterTexture.copyPixelBuffer` |
| `android/.../VideoUltraPlayerPlugin.kt` | reescrever | registrar channels, `TextureRegistry` surface, delegar ao controller |
| `android/.../TimelineCompositionController.kt` | criar | `CompositionPlayer` + `Composition`/`EditedMediaItemSequence` + estado |
| `android/build.gradle` | editar | adicionar dependências Media3 (`media3-transformer`, `media3-effect`, `media3-common`) |
| `pubspec.yaml` | editar | `description` real; remover comentários de template |
| `example/lib/main.dart` | reescrever | demo: carregar timeline de clipes, `Texture`, controles e scrub |
| `example/assets/` | criar | clipes de vídeo + imagem de amostra para o demo |
| `test/native_timeline_player_test.dart` | criar | testes do contrato Dart (mock do platform interface) |

```
Flutter (Dart)
  NativeTimelinePlayer
    └─ MethodChannel 'video_ultra_player/timeline_player'  → load/play/pause/seekTo/setVolume/setClipAlignment/dispose
    └─ EventChannel  'video_ultra_player/timeline_player/events' ← TimelinePlayerState
    └─ Texture(textureId)
        │
   ┌────┴─────────────────────────┐
 iOS                            Android
 AVMutableComposition           CompositionPlayer
 + AVVideoComposition           + Composition / EditedMediaItemSequence
 + AVPlayerItemVideoOutput      + SurfaceTexture(TextureRegistry) → Surface
   → FlutterTexture
```

## Fases

### Fase 0 — Scaffolding e limpeza do skeleton

- [ ] Atualizar `pubspec.yaml`: `description` real do plugin; remover blocos de comentário de template.
- [ ] Criar a estrutura `lib/src/{models,}` e o arquivo `lib/src/native_timeline_player.dart` (vazio por enquanto).
- [ ] Confirmar `pluginClass`/`package` em `pubspec.yaml` (já corretos: `VideoUltraPlayerPlugin` / `com.andre.video_ultra_player`).
- [ ] Verificação: `flutter analyze` passa sem erros novos; o pacote ainda compila com o stub atual.

### Fase 1 — Modelos Dart (`TimelineClip`, `MediaType`, `TimelinePlayerState`)

- [ ] Criar `lib/src/models/timeline_clip.dart`: `enum MediaType { video, image }`; `class TimelineClip` com `path`, `type`, `duration?`, `alignment` (`Alignment`), `scale`, `const` constructor, e `Map<String,dynamic> toJson()` (durations em ms, alignment como `x`/`y`).
- [ ] Criar `lib/src/models/timeline_player_state.dart`: `TimelinePlayerState` (`globalPosition`, `clipIndex`, `localPosition`, `isPlaying`, `totalDuration` como `Duration`) + `factory TimelinePlayerState.fromMap(Map)` convertendo ms→`Duration`.
- [ ] Verificação: `flutter analyze` limpo; modelos são `const`-friendly e imutáveis.

### Fase 2 — Testes do contrato Dart (TDD: antes da implementação do channel)

> Escreva os testes que definem o comportamento da API pública. Eles vão falhar até a Fase 3/4 existirem.

- [ ] Criar `test/native_timeline_player_test.dart` com um `MockVideoUltraPlayerPlatform` (extends `VideoUltraPlayerPlatform` com mock token).
- [ ] Testar `load(clips)`: encaminha lista serializada (`toJson`) ao platform interface.
- [ ] Testar `play/pause/seekTo/setVolume/setClipAlignment/dispose`: cada um chama o método correspondente com os args certos (`seekTo` converte `Duration`→ms; `setVolume` valida faixa 0.0–1.0).
- [ ] Testar `stateStream`: emite `TimelinePlayerState` a partir de um `Map` simulado do EventChannel.
- [ ] Testar `textureId`: reflete o id retornado por `load`.
- [ ] Verificação: `flutter test` compila e os testes **falham pelos motivos certos** (métodos não implementados), não por erro de sintaxe.

### Fase 3 — Platform interface + Method/Event channel (Dart)

- [ ] Reescrever `lib/video_ultra_player_platform_interface.dart`: remover `getPlatformVersion`; declarar `Future<int> load(List<Map> clips)`, `play/pause/seekTo/setVolume/setClipAlignment/dispose`, `Stream<TimelinePlayerState> stateStream(int textureId)`.
- [ ] Reescrever `lib/video_ultra_player_method_channel.dart`: `MethodChannel('video_ultra_player/timeline_player')` para comandos; `EventChannel('video_ultra_player/timeline_player/events')` mapeado para `TimelinePlayerState.fromMap`.
- [ ] Implementar `lib/src/native_timeline_player.dart`: classe `NativeTimelinePlayer` delegando ao platform interface; guarda `textureId`; expõe `stateStream`.
- [ ] Atualizar `lib/video_ultra_player.dart`: re-exportar `NativeTimelinePlayer`, `TimelineClip`, `MediaType`, `TimelinePlayerState`; remover a classe `VideoUltraPlayer` stub.
- [ ] Verificação: `flutter test` — todos os testes da Fase 2 passam.

### Fase 4 — Android: spike de maturidade do `CompositionPlayer`

> O overview marca `CompositionPlayer` como API nova/experimental (Risco Alto). Validar antes de comprometer.

- [ ] Fixar versão do Media3 em `android/build.gradle` (`media3-transformer`, `media3-effect`, `media3-common`) e registrar a versão exata.
- [ ] Spike curto: instanciar `CompositionPlayer` com uma `EditedMediaItemSequence` de 2 vídeos heterogêneos + 1 imagem (`setImageDurationMs`) e renderizar numa `Surface` de teste.
- [ ] Confirmar suporte a imagem na versão fixada; se não houver, anotar o fallback (pré-encode de vídeo curto a partir da imagem).
- [ ] Verificação: registrar no plano (ou num comentário no controller) se `CompositionPlayer` é viável ou se entra o fallback ExoPlayer playlist (com caveat de transição no boundary).

### Fase 5 — iOS: composição nativa + render para textura

- [ ] Criar `ios/Classes/TimelineComposition.swift`: monta `AVMutableComposition` (track de vídeo + áudio) inserindo cada clipe como segmento contíguo; constrói `AVVideoComposition` com `AVMutableVideoCompositionInstruction`/`LayerInstruction` por segmento (preferredTransform + scale/crop/alignment).
- [ ] Imagens: implementar `AVVideoCompositing` custom que emite o `CVPixelBuffer` da imagem no intervalo do clipe (fallback documentado: pré-gerar vídeo curto). **Não** usar `AVVideoCompositionCoreAnimationTool` (é orientado a export).
- [ ] Criar `ios/Classes/TimelineTexture.swift`: `AVPlayerItemVideoOutput` + `CADisplayLink` → implementar `FlutterTexture.copyPixelBuffer(forItemTime:)` (`AVPlayerLayer` não é capturável).
- [ ] Reescrever `ios/Classes/VideoUltraPlayerPlugin.swift`: registrar `FlutterMethodChannel`/`FlutterEventChannel` com os nomes do pacote; `load` cria composição + `AVPlayer` + registra `FlutterTexture` no `registrar.textures()` e retorna `textureId`.
- [ ] Implementar `play/pause/seekTo` (seek final com tolerância **zero**; scrub com tolerância não-zero), `setVolume`, `setClipAlignment(index,x,y)` (atualiza `LayerInstruction`/transform sem recriar a composição).
- [ ] `periodicTimeObserver` (~33ms) → calcular `clipIndex` cruzando posição com a tabela de segmentos → emitir `TimelinePlayerState` pelo EventChannel; `didPlayToEndTime` → fim/loop.
- [ ] Verificação: rodar `example/` no simulador/dispositivo iOS — timeline reproduz gapless, seek e alignment funcionam, estado chega no Dart.

### Fase 6 — Android: `CompositionPlayer` + render para textura

> Se a Fase 4 indicar inviabilidade, usar o fallback ExoPlayer playlist documentado.

- [ ] Criar `android/.../TimelineCompositionController.kt`: monta `Composition` com uma `EditedMediaItemSequence` (vídeos como `EditedMediaItem`; imagens via `MediaItem.Builder().setImageDurationMs(...)`); instancia `CompositionPlayer`.
- [ ] Render: obter `SurfaceTexture` do `TextureRegistry` do Flutter → envolver em `Surface` → entregar ao player (não capturar `SurfaceView`); retornar `textureId`.
- [ ] Reescrever `android/.../VideoUltraPlayerPlugin.kt`: registrar `MethodChannel`/`EventChannel` com os nomes do pacote; delegar comandos ao controller; expor `textureId` no retorno de `load`.
- [ ] Implementar `play/pause/seekTo` (seek por posição global em ms; scrub aproximado), `setVolume`, `setClipAlignment` (via `Effects`/`VideoEffects` por `EditedMediaItem`, ou transform no widget `Texture` do lado Flutter).
- [ ] Derivar `clipIndex` da posição global × tabela de durações da sequência → emitir `TimelinePlayerState` pelo EventChannel (boundary é interno à composição, não `onMediaItemTransition`).
- [ ] Verificação: rodar `example/` em dispositivo/emulador Android — playback gapless, seek, alignment e stream de estado funcionando.

### Fase 7 — Implementar o demo em `example/`

> Entrega final pedida: o player precisa ser exercitado de ponta a ponta no app de exemplo.

- [ ] Adicionar assets de amostra em `example/assets/` (2–3 vídeos curtos + 1 imagem) e declará-los em `example/pubspec.yaml`.
- [ ] Reescrever `example/lib/main.dart`: substituir o demo de `getPlatformVersion` por uma tela que copia os assets para arquivos locais (file paths absolutos), monta `List<TimelineClip>` e chama `player.load(clips)`.
- [ ] Renderizar `Texture(textureId: player.textureId)` dentro de um `AspectRatio`; adicionar botões Play/Pause, slider de scrub ligado a `seekTo`, e um indicador `clipIndex/total` + posição via `StreamBuilder(player.stateStream)`.
- [ ] Adicionar um `GestureDetector` de pan sobre o `Texture` chamando `setClipAlignment(index, x, y)` para validar crop/pan ao vivo.
- [ ] Chamar `player.dispose()` no `dispose()` do State.
- [ ] Verificação: `flutter run` em iOS e Android a partir de `example/` — a timeline reproduz sem gap no boundary, scrub/seek respondem, indicador de clipe atualiza, pan ajusta o alignment.

## Critérios de Sucesso

- [ ] Uma única textura GPU para toda a timeline (sem swap de texture) em ambas as plataformas.
- [ ] Composição nativa real (`AVMutableComposition` no iOS / `CompositionPlayer` no Android) com gapless verdadeiro no boundary.
- [ ] `seekTo` frame-accurate por posição global em ms; scrub fluido com tolerância aproximada.
- [ ] `stateStream` emite `globalPosition`, `clipIndex`, `localPosition`, `isPlaying`, `totalDuration`.
- [ ] Imagens suportadas como clipes com duração configurável.
- [ ] `setClipAlignment(index, x, y)` atualiza crop/pan sem recriar a composição.
- [ ] `example/` roda em iOS e Android demonstrando todos os controles.
- [ ] Build sem erros (`flutter analyze` limpo).
- [ ] Todos os testes unitários Dart passando (`flutter test`).

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `CompositionPlayer` (Media3) imaturo na versão fixada — sequências/formatos/surface limitados | Alta | Spike da Fase 4 antes de comprometer; fallback ExoPlayer playlist documentado com caveat de transição no boundary |
| Imagens na composição não suportadas (iOS `AVVideoCompositing` custom é complexo / Media3 sem suporte na versão) | Média | Fallback comum: pré-gerar vídeo curto a partir da imagem e inserir como segmento de vídeo normal |
| Render para textura com performance baixa / frame drops (`copyPixelBuffer` a 33ms) | Média | Usar o mesmo mecanismo do `video_player` oficial (`AVPlayerItemVideoOutput` + `CADisplayLink`); medir no demo |
| Seek com tolerância zero trava o arrasto durante scrub | Média | Tolerância não-zero durante scrub, zero só no seek final (já previsto na Fase 5/6) |
| Vídeos heterogêneos (resoluções/codecs) causam reset de renderer no boundary (Android) | Média | É exatamente a razão de preferir `CompositionPlayer` sobre playlist; validar no spike |

## Rollback

O skeleton atual é boilerplate de plugin sem dependentes neste repositório. Rollback = reverter os arquivos editados/criados ao estado de `flutter create --template=plugin` (`getPlatformVersion` em Dart/iOS/Android e o `example/lib/main.dart` original). As fases são sequenciais e isoladas por plataforma — é possível reverter apenas iOS (Fase 5) ou apenas Android (Fase 6) mantendo a camada Dart (Fases 1–3).

## Após a Implementação

> Perguntar ao usuário: "Deseja criar um flow dessa funcionalidade em `./flow/`? Ele documenta o caminho completo do fluxo (UI → Cubit → Repository → DataSource) e serve de referência para futuros planos e revisões."

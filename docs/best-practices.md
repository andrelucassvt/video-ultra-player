# Melhores Práticas — Editor de Vídeo (`video_ultra_player`)

Guia consolidado das práticas que este projeto já segue (e que qualquer feature nova deve seguir) para implementar um editor de vídeo com preview gapless nativo, edição em timeline e export MP4. Derivado dos flows em `docs/flow/` e do `AGENTS.md`.

## 1. Arquitetura federada em 4 camadas

- Toda capacidade nova nasce nas quatro camadas, nesta ordem: `VideoUltraPlayerPlatform` (contrato em `lib/video_ultra_player_platform_interface.dart`) → `MethodChannelVideoUltraPlayer` (`lib/video_ultra_player_method_channel.dart`) → iOS (`ios/Classes/`) **e** Android (`android/src/main/kotlin/.../`), sempre as duas.
- A API pública (`lib/src/native_timeline_player.dart`) valida entradas e delega — **nunca** instancia `MethodChannel` diretamente.
- Paridade iOS/Android faz parte do contrato: nunca entregue uma capacidade em uma plataforma só.
- Nome do channel = nome do pacote (`video_ultra_player/...`).
- O `textureId` devolvido pelo `load` é a identidade da sessão: todo comando seguinte o carrega e o nativo resolve o controller no mapa `textureId → controller`.

## 2. Regra de ouro: export = preview

- Preview e export compartilham o mesmo estado nativo. O export reconstrói a partir da **mesma lista de clipes editada** e da **mesma config** (`buildCurrentExportAsset` no iOS, `startExportCurrentTimeline` no Android).
- Qualquer efeito novo precisa viver no pipeline compartilhado pelas duas operações — se só aparece no preview, é bug de design, não feature.
- `exportTimeline(clips)` e `exportCurrentTimeline()` têm semânticas diferentes (a primeira ignora a trilha de áudio externa; a segunda inclui). Documente e respeite essa diferença ao mexer no export.

## 3. Preview em textura nativa

- `AVPlayerLayer` (iOS) e `SurfaceView` (Android) **não** são capturáveis para textura. Use `AVPlayerItemVideoOutput.copyPixelBuffer` (iOS) e `SurfaceTexture` do `TextureRegistry` (Android).
- iOS: anexe o `AVPlayerItemVideoOutput` ao item **antes** de entregá-lo ao `AVPlayer`; um seek de tolerância zero no primeiro `readyToPlay` é o que faz o primeiro frame aparecer pausado. Um output por item — `replacePlayerItem` cuida de desanexar do antigo.
- O Flutter desenha só um `Texture(textureId:)`; todo o pipeline de vídeo fica no nativo.

## 4. Modelo de dados e unidades

- **Tudo em milissegundos no channel**; o Dart converte para `Duration` nas bordas (`TimelinePlayerState.fromMap`).
- **`trimEnd` é ponto absoluto na fonte, não duração** — e tem precedência sobre `duration` para vídeo (`effectiveRange` iOS / `resolvedDurationMs` Android). Ao implementar trim, zere/descarte `durationMs` para não deixar duas fontes de duração concorrendo.
- Imagem ignora trim: usa `duration` (fallback 2000 ms) e vira vídeo (MP4 temporário via `AVAssetWriter` no iOS; `setImageDurationMs` + frame rate no Android).
- `renderSize` sempre em dimensões **pares** (requisito dos encoders H.264) e rotação da fonte respeitada (transform no iOS; inversão de largura/altura quando rotação é 90/270 no Android).
- Valide em Dart antes de tocar o channel: timeline não vazia (`ArgumentError`), `speed` em `[0.5, 2.0]` (`RangeError`), `volume` em `[0.0, 1.0]`, índices negativos. O nativo reforça com clamp, mas a API pública falha cedo e com mensagem clara.

## 5. Edição da timeline: o ciclo snapshot → mutar → rebuild

- Toda mutação nativa segue exatamente: `pushEditSnapshot()` → alterar a lista de clipes → rebuild **preservando `textureId` e posição** (`rebuildPreservingPlayback` / `rebuildCompositionPreservingPlayback` — nunca re-registram a textura; no Android também restaura `play()` se estava tocando, com posição clampada).
- `pushSnapshot` limpa a pilha de redo; histórico limitado a 50 snapshots; snapshot guarda **metadados** (descritores + trilha de áudio), nunca cópia de mídia.
- Índices fora de faixa: Dart barra negativos; o nativo ignora silenciosamente (`guard`/`return`) — as duas camadas por motivos diferentes, e ambas são intencionais.
- `removeClip` no último clipe é permitido pelo plugin; quem impede é a camada de app (o exemplo exige `clips.length > 1`).

## 6. Comandos de edição só no commit do gesto

- Efeitos nativos são caros e/ou imutáveis: no Android **todo** comando reconstrói a `Composition` (até `setClipAlignment`; efeitos Media3 são imutáveis). No iOS, speed/trim também são rebuild.
- Portanto: trim, velocidade, volume e alignment são chamados **no release do gesto**, nunca a cada tick de arrasto. Durante o arrasto, atualize só a UI local (largura visual, slider, `_draftWidth`).
- `EditedMediaItem.setDurationUs` (Android) recebe a duração **da fonte**, não a cortada — senão o Media3 rejeita `clippingEndPositionMs` quando `trimStart > 0`.

## 7. Playback e scrub

- Scrub usa **seek throttled**: o arrasto do playhead enfileira posições e libera no máximo um seek a cada 16 ms (`previewSeek`); ao soltar, `commitSeek` cancela o timer e faz o seek definitivo.
- A timeline não faz loop: ao dar play faltando <100 ms para o fim, faça seek para zero antes.
- Durante o arrasto, mantenha a posição num `_dragPosition` local — o playhead se move imediatamente, sem esperar o estado assíncrono do nativo (evita o "puxão").
- Erro de playback no Android chega como **erro do stream** (`playback_error` pelo EventChannel), não como exceção de método — capture com `StreamBuilder`/`onError` e apresente na UI.

## 8. Espelho local dos clipes na UI

- O nativo devolve durações, **não** a lista de clipes. Depois de cada mutação bem-sucedida, a UI atualiza seu próprio `_clips` (`_splitLocalClip`, `copyWith`, `removeAt`).
- A réplica precisa ser fiel à semântica nativa (ex.: o split local multiplica a posição por `speed`, igual ao nativo).
- Undo/redo só habilita quando **nativo e local concordam** (`state.canUndo && controller.canUndo`); cada um mantém sua pilha e o controller restaura o snapshot local após o undo nativo.

## 9. Thumbnails

- Extração é utilitário standalone (`generateThumbnails`), não exige `load`, e **nunca roda na main thread** (fila global no iOS, executor dedicado no Android).
- Cache em disco por `(videoPath, timestampMs, width)` — segunda chamada idêntica é servida do disco.
- Timestamps que falham são **omitidos** do resultado (a lista pode vir menor); a UI precisa ter fallback (`_ClipFallbackIcon`).
- Limite a quantidade por clipe (o exemplo usa no máximo 5) e **invalide o cache de requisições a cada edição** (trim, split, remove, move, speed, troca de timeline).
- iOS é frame-exato, Android é keyframe (`OPTION_CLOSEST_SYNC`) — não compare frames entre plataformas.

## 10. Trilha de áudio sobreposta

- Uma trilha externa por player; `setAudioTrack` substitui; entra no histórico de undo junto com os clipes.
- A duração é **capada pela timeline** (`min(trimmedDuration, timelineDuration - offset)`) — no Android é exigência do Media3 para casar `durationUs` com o clipping.
- A trilha não estende a timeline: áudio além do fim é cortado; offset além do fim é ignorado.
- iOS: só crie a trilha de áudio da composição se algum clipe tiver áudio (guard `hasAnyClipAudio`) — sem isso o load falha silenciosamente.
- Fades são lineares (`setVolumeRamp` no iOS; ganho por posição de sample no Android).

## 11. Export

- Um export por instância de player (`StateError` em Dart fora disso); o canal de progresso é global (sem `textureId`) — não exponha dois exports simultâneos na mesma UI.
- Destino default é diretório temporário com UUID no nome; **o app é responsável por persistir** (o exemplo salva na galeria com `gal` e apaga o temporário).
- Arquivo de saída existente é sobrescrito (remova antes); em falha, apague o arquivo parcial e emita `state: "failed"`.
- Progresso sempre clampado em `[0, 1]` na emissão e no parse; estado inicial `idle` emitido no `onListen`.
- Engine desanexada no meio do export: cancele os exporters ativos e não reporte mais nada.

## 12. UI do editor (app de exemplo)

- Estado com `ChangeNotifier` puro em um único `EditorController` — **não** recrie Clean Architecture de app (sem Cubits, GetIt, GoRouter): este repo é um plugin, o exemplo é demonstração.
- Combine dois níveis de reatividade: `AnimatedBuilder` no controller (estado do app) + `StreamBuilder<TimelinePlayerState>` no `stateStream` (posição/playback do nativo).
- Interações padrão: tocar no clipe seleciona **e** faz seek para ele; long-press arrasta para reordenar (`LongPressDraggable`/`DragTarget`); tocar na régua faz seek direto; alças de trim só no clipe selecionado.
- Largura de cada tile de clipe proporcional à duração resolvida (`clipDurations` do nativo, com fallback calculado de trim/duration/speed até o primeiro report).
- Timeline: cabeçalhos de faixa fixos fora do scroll horizontal; playhead cruza régua e faixas; zoom via `pixelsPerSecond` com clamp (44–132).
- Toolbar densa deve ser rolável horizontalmente para não estourar em telas estreitas.

## 13. Erros: códigos previsíveis por camada

- Dart: `StateError` para chamadas fora de ordem (sem `load`, export concorrente), `ArgumentError`/`RangeError` para entrada inválida.
- Nativo: códigos estáveis — `not_attached`, `invalid_arguments`, `invalid_clip`, `load_failed`, `not_found`, `edit_failed`, `export_failed`. Mensagem real em `details`.
- No app, todo erro vira mensagem numa status bar única — nunca `print()`; use `log()` de `dart:developer` quando precisar registrar.

## 14. Testes e verificação

- Dart: testes unitários dos modelos, do player com platform fake e dos payloads do method channel (`flutter test` na raiz).
- Android: testes Kotlin do plugin (`cd example/android && ./gradlew testDebugUnitTest`).
- UI do exemplo: widget tests headless montando o shell com `autoLoad: false`.
- Verificação se limita a análise estática, build e testes no harness — **nunca** suba app/emulador para validar; o teste funcional é manual, do usuário.

## 15. Checklist para qualquer feature nova

1. Contrato no `platform_interface` + implementação no `method_channel`.
2. iOS **e** Android com paridade (incluindo códigos de erro).
3. Efeito presente no pipeline de preview **e** de export.
4. Snapshot no histórico **antes** de mutar (se for edição).
5. Rebuild preservando `textureId` e posição de playback.
6. Chamada nativa só no commit do gesto (se houver arrasto).
7. Espelho local de clipes atualizado + cache de thumbnails invalidado.
8. Testes Dart (payload + player fake) e, se mexer no Kotlin, testes de unidade Android.
9. Flow em `docs/flow/` criado ou atualizado.

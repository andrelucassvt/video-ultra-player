---
generated_at: 2026-08-01
source_commit: 1e11b62
source_state: clean
verified_at: 2026-08-01
status: current
related_plans:
  - docs/plan/onda-2-identidade-editor.md
  - docs/plan/editor-ui-redesign-light.md
---

# Flow: App de Exemplo (Editor)

> **Resumo:** O app em `example/` é um editor de vídeo em tema claro que consome o plugin: preview em `Texture`, toolbar única (playback, ações de edição, undo/redo, zoom e export), timeline com cabeçalhos de faixa fixos à esquerda, edição por gesto e export para a galeria.

## Visão Geral

`main.dart` monta `TimelineEditorApp` (um `MaterialApp` com `editorTheme` claro) e abre `EditorScreen(autoLoad: true)`. A tela cria um `EditorController` no `initState` e, no primeiro frame, chama `loadSample()`.

`EditorController` é um `ChangeNotifier` — não há Cubit, GetIt nem router aqui. Ele é o único ponto que fala com `NativeTimelinePlayer` e concentra: lista local de clipes (`_clips`), trilha de áudio, `textureId`, clipe selecionado, aspect ratio e `baseWidth`, zoom da timeline (`pixelsPerSecond`), estados de `loading`/`exporting`/`error`, cache de requisições de thumbnail, throttle de seek e um par de pilhas de undo/redo espelhando o histórico nativo.

O `build` da `EditorScreen` combina dois níveis de reatividade: um `AnimatedBuilder` no controller (mudanças de estado do app) e, dentro dele, um `StreamBuilder<TimelinePlayerState>` no `controller.stateStream` (posição e estado de playback vindos do nativo), com `TimelinePlayerState.initial()` como `initialData`. Erros do stream — inclusive o `playback_error` que o Android empurra pelo `EventChannel` — são capturados por `_capturePlaybackError` e viram mensagem na status bar.

A tela é uma `Column`: `EditorTopBar` (reset, menu de origem da timeline e resolução 720p/1080p), `PreviewArea` (`Texture` + pan/crop por arrasto), `EditorToolbar` (play circular + tempo, dividir/velocidade/proporção/excluir, undo/redo, slider de zoom e export com percentual — rolável horizontalmente em telas estreitas), `TimelineSection` (coluna fixa de lane headers + régua, faixa de clipes, faixa de áudio e playhead em scroll horizontal) e uma status bar condicional no fim.

Duas convenções de interação atravessam a UI. A primeira: **scrub usa seek throttled, edição commita no release**. O arrasto do playhead chama `previewSeek`, que enfileira a posição e libera no máximo um seek a cada 16 ms; ao soltar, `commitSeek` cancela o timer e faz o seek definitivo. Trim, velocidade e volume só chamam o nativo no fim do gesto, porque cada um desses comandos reconstrói a composição. A segunda: **a UI mantém um espelho local dos clipes**. Depois de cada mutação bem-sucedida o controller atualiza `_clips` por conta própria (`_splitLocalClip`, `copyWith`, `removeAt`), porque o nativo devolve apenas durações — não a lista de clipes.

O carregamento de mídia tem três origens: os assets do demo (copiados para `systemTemp` porque o nativo só trabalha com paths de arquivo), a galeria via `ImagePicker.pickMultiVideo` e o áudio via `FilePicker`. Toda troca de timeline passa por `replaceTimeline`, que dispõe o player anterior, carrega a nova lista, reaplica a trilha de áudio se houver e reseta seleção, caches e histórico.

## Passo a Passo

1. **Bootstrap** — `example/lib/main.dart` → `TimelineEditorApp`
   `MaterialApp(theme: editorTheme, home: EditorScreen(autoLoad: true))`.
2. **Criação do controller** — `example/lib/editor/editor_screen.dart` → `initState`
   `EditorController()` e `addPostFrameCallback` → `loadSample()`.
3. **Carga do sample** — `example/lib/editor/editor_controller.dart` → `loadSample` → `_copyAssetToTempFile`
   Copia `assets/clip_a.mp4`, `assets/still.png` e `assets/clip_b.mp4` para `systemTemp/video_ultra_player_example` e monta três `TimelineClip` (vídeo 2 s com `scale: 1.05`, imagem 1600 ms com `scale: 1.3`, vídeo 2 s).
4. **Troca de timeline** — `replaceTimeline(clips, source:, audioTrack:)`
   `_player.dispose()` → `_player.load(clips, config: compositionConfig)` → `setAudioTrack` se houver → guarda `textureId`, `stateStream`, `_clips` → limpa seleção, caches, histórico e erro.
5. **Origem alternativa** — `EditorTopBar` → `PopupMenuButton` → `loadSample()` / `pickVideos()`
   `pickVideos` usa `ImagePicker.pickMultiVideo()` e converte cada `XFile.path` em `TimelineClip(type: MediaType.video)`.
6. **Reatividade** — `EditorScreen.build` → `AnimatedBuilder` + `StreamBuilder<TimelinePlayerState>`
   `_capturePlaybackError` converte erro do stream em `controller.setPlaybackError`.
7. **Preview** — `example/lib/editor/widgets/preview_area.dart`
   `Texture(textureId:)` dentro de `AspectRatio` derivado de `previewAspectRatio` (`null` para `original`); `onPanUpdate` converte a posição local em `x/y` em `[-1, 1]` e chama `controller.setClipAlignment(state.clipIndex, x, y)`.
 8. **Playback** — `example/lib/editor/widgets/editor_toolbar.dart` → `controller.playOrPause(state)`
    Se a posição está a menos de 100 ms do fim, dá seek para zero antes do `play` (a timeline nativa não faz loop).
 9. **Timeline** — `example/lib/editor/widgets/timeline_section.dart`
    `contentWidth` derivado de `pixelsPerSecond`; `Row` com a coluna fixa de lane headers (`_LaneHeaderColumn`, ~40 px, ícones de filme e áudio fora do scroll) e o scroll horizontal que empilha `TimelineRuler`, `ClipStrip`, `AudioTrackRow` e `TimelinePlayhead` num `Stack`. Tempo e zoom vivem na `EditorToolbar`, não mais num header interno.
10. **Scrub** — `_startPlayheadDrag` / `_updatePlayheadDrag` / `_endPlayheadDrag`
    Converte pixels em `Duration`, mostra `_dragPosition` localmente e chama `previewSeek` (throttle de 16 ms) e `commitSeek` no fim. Toque na régua vai direto para `commitSeek`.
11. **Faixa de clipes** — `example/lib/editor/widgets/clip_strip.dart`
    Largura de cada tile proporcional à duração resolvida; `InkWell` → `selectClip` (que também faz `seekToClip`); `LongPressDraggable`/`DragTarget` → `moveClip`; `_ClipThumbnailRail` busca thumbnails do clipe.
12. **Trim** — `example/lib/editor/widgets/clip_trim_handles.dart`
    Aparece só no clipe selecionado; ajusta a largura visual durante o arrasto (`onVisualWidthChange`) e chama `controller.trimClip` no release.
 13. **Toolbar** — `example/lib/editor/widgets/editor_toolbar.dart`
     Dividir → `controller.split(state)`; Velocidade → `showSpeedSheet` (slider 0.5–2.0 + chips, commit em `onChangeEnd`); Proporção → `showAspectRatioSheet`; Excluir → `removeSelected` (só com mais de um clipe).
14. **Áudio** — `example/lib/editor/widgets/audio_track_row.dart`
    Vazio → `addAudioTrack` (`FilePicker` com extensões de áudio); ativo → slider de volume (`setAudioVolumePreview` no arrasto, `commitAudioVolume` no release) e remover.
15. **Config de saída** — `setAspectRatio` / `setBaseWidth`
    Alteram `compositionConfig` e chamam `reload()`, que refaz `replaceTimeline` com os mesmos clipes e a mesma trilha.
 16. **Export** — `EditorToolbar._ExportButton` → `controller.export`
    Cria `systemTemp/video_ultra_player_example_exports`, chama `exportCurrentTimeline(outputPath:)`, assina `exportProgress` para o percentual, salva na galeria com `Gal.putVideo` e apaga o temporário.
 17. **Undo/redo** — `EditorToolbar` → `controller.undo()` / `redo()`
    Habilitados só quando o estado nativo (`state.canUndo/canRedo`) **e** as pilhas locais concordam; o controller chama o nativo e restaura o snapshot local.
18. **Encerramento** — `EditorScreen.dispose` → `EditorController.dispose`
    Cancela o timer de seek e dispõe o `NativeTimelinePlayer`.

### Caminhos alternativos

- **Picker cancelado:** `pickVideos` encerra o loading e mantém a timeline; `addAudioTrack` retorna sem alterar nada.
- **`PlatformException` no picker:** exibida na status bar; código `multiple_request` no áudio é ignorado.
- **Erro em qualquer operação:** `_setError` preenche `_error` e a `_EditorStatusBar` vermelha aparece no fim da coluna.
- **Erro de playback:** `_capturePlaybackError` formata `PlatformException` (`code` + `message`) e chama `setPlaybackError`, que só registra se não houver erro anterior.
- **Permissão de galeria negada:** `_saveToGallery` lança e o erro vira mensagem na status bar.
- **Timeline vazia:** `ClipStrip` mostra `_EmptyClipStrip` ("Load a sample or choose videos") e a toolbar fica desabilitada.
- **Sem `textureId`:** `PreviewArea` mostra `_PreviewPlaceholder` (spinner durante `loading`, ícone caso contrário).
- **`clipDurations` ainda não reportado:** `resolvedClipDurations` cai em `_fallbackClipDuration`, que calcula a partir de trim/duration dividido por `speed`.
- **Split no fim do clipe:** `split` retorna sem fazer nada quando `localPosition >= duration`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Bootstrap | `example/lib/main.dart` | `TimelineEditorApp`, tema, home |
| Tela | `example/lib/editor/editor_screen.dart` | Composição da coluna, `StreamBuilder`, captura de erro de playback, status bar |
| Estado | `example/lib/editor/editor_controller.dart` | Toda a orquestração do plugin e o espelho local dos clipes |
 | Tema | `example/lib/editor/theme/editor_theme.dart` | Paleta clara (`editorAccent` teal, `editorBackground` branco, `editorSurface`, `editorSurfaceHigh`, `editorLine`, `editorTextMuted`, `editorText`) e `editorTheme` light |
 | Widget | `example/lib/editor/widgets/editor_top_bar.dart` | Reset, origem da timeline e resolução |
 | Widget | `example/lib/editor/widgets/editor_toolbar.dart` | Play circular + tempo, dividir/velocidade/proporção/excluir, undo/redo, slider de zoom e export com progresso (linha única rolável) |
 | Widget | `example/lib/editor/widgets/preview_area.dart` | `Texture`, `AspectRatio`, pan/crop por gesto, placeholder |
 | Widget | `example/lib/editor/widgets/timeline_section.dart` | Layout da timeline, coluna fixa de lane headers, scroll e scrub do playhead |
 | Widget | `example/lib/editor/widgets/timeline_ruler.dart`, `timeline_ruler_painter.dart` | Régua de segundos (rótulos `mm:ss` a cada 5 s) e seu `CustomPainter` |
 | Widget | `example/lib/editor/widgets/timeline_playhead.dart` | Agulha arrastável (linha fina escura cruzando régua e faixas) |
| Widget | `example/lib/editor/widgets/clip_strip.dart` | Tiles proporcionais, seleção, reordenação, rail de thumbnails |
| Widget | `example/lib/editor/widgets/clip_trim_handles.dart` | Alças de trim do clipe selecionado |
 | Widget | `example/lib/editor/widgets/audio_track_row.dart` | Faixa de áudio, volume, remoção |
 | Widget | `example/lib/editor/widgets/speed_sheet.dart`, `aspect_ratio_sheet.dart` | Bottom sheets de velocidade e proporção |
| Assets | `example/assets/clip_a.mp4`, `still.png`, `clip_b.mp4` | Mídia do sample (declarada em `example/pubspec.yaml`) |
| Config | `example/pubspec.yaml` | Dependência local no plugin, `image_picker`, `file_picker`, `gal`, assets |
| Testes | `example/test/widget_test.dart` | Widget test do app de exemplo |
| Testes | `example/integration_test/plugin_integration_test.dart` | Teste de integração do exemplo |

## Regras de Negócio Relevantes

- **Assets precisam virar arquivo** — `_copyAssetToTempFile`: o nativo só aceita paths de arquivo, então os assets são gravados em `systemTemp` antes do `load`.
- **Troca de timeline sempre dispõe a anterior** — `replaceTimeline` chama `_player.dispose()` antes do novo `load`.
- **Play no fim reinicia** — `playOrPause` faz seek para zero quando falta menos de 100 ms para o fim.
- **Scrub é throttled em 16 ms** — `previewSeek`/`_flushPreviewSeek`; `commitSeek` cancela o timer e faz o seek final.
- **Edição commita no release** — trim, velocidade e volume de áudio só chamam o nativo no fim do gesto, porque cada comando reconstrói a composição.
- **`selectClip` também faz seek** — seleciona o índice e chama `seekToClip`.
- **Excluir exige mais de um clipe** — `removeSelected` retorna se `_clips.length <= 1`.
- **`pixelsPerSecond` entre 44 e 132** — `setPixelsPerSecond` faz clamp; define a escala de toda a timeline.
- **`baseWidth` entre 1 e 4096** — `setBaseWidth` faz clamp; o menu oferece 720 e 1080.
- **Mudar proporção ou resolução recarrega** — `setAspectRatio`/`setBaseWidth` chamam `reload()`, que refaz o `load` com a config nova.
- **Undo exige acordo entre nativo e local** — a `EditorToolbar` usa `state.canUndo && controller.canUndo`; o controller mantém `_undoSnapshots`/`_redoSnapshots` com limite de 50.
- **Espelho local após cada mutação** — o controller atualiza `_clips` explicitamente (`_splitLocalClip` replica a semântica de trim do nativo, inclusive multiplicando a posição local por `speed`).
- **Cache de thumbnails invalidado em toda edição** — `_thumbnailRequests.clear()` após trim, split, remove, move, speed e troca de timeline.
- **Export vai para a galeria** — `Gal.requestAccess` + `Gal.putVideo`, e o temporário é apagado; `exportPath` volta a `null` e a UI mostra "Salvo na galeria".
- **`_notify` respeita o dispose** — `notifyListeners` só é chamado se `_disposed` for `false`.

## Dependências Externas

- **`video_ultra_player`** — via `path: ../`.
- **`image_picker ^1.2.2`** — `pickMultiVideo()`.
- **`file_picker ^11.0.2`** — áudio (`mp3`, `aac`, `m4a`, `wav`, `flac`, `ogg`, `opus`).
- **`gal ^2.3.1`** — `requestAccess` e `putVideo`.
- **Permissões nativas** — `example/ios/Runner/Info.plist` e o manifest do app Android precisam declarar acesso a biblioteca/galeria para os pickers e o `gal`.

## Observações

- Estado é `ChangeNotifier` puro: nenhuma camada de domínio/data, nenhum DI — é um app de demonstração, e as instruções do projeto proíbem recriar aqui a Clean Architecture de app.
- Textos estão hardcoded e misturam português e inglês ("Adicionar audio", "Exportar", "Load a sample or choose videos", "Sample"/"Clips"); não há l10n.
- O campo `_editBusy` é `final bool _editBusy = false` e o getter `editBusy` sempre devolve `false` — resíduo sem efeito.
- O `_title` é fixo (`'Meu vídeo'`) e `_timelineSource` é registrado mas não exibido em nenhum widget.
- `_dragPosition` vive no `_TimelineSectionState`, então durante o arrasto o playhead se move localmente antes de o estado nativo confirmar — é o que evita o "puxão" do seek assíncrono.
- `AudioTrackRow` desenha a trilha com largura mínima de 220 px: o bloco não representa a duração real do áudio.

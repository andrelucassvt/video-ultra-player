---
generated_at: 2026-08-01
source_commit: cf6ee32
source_state: dirty
verified_at: 2026-08-02
status: current
related_plans:
  - docs/plan/onda-2-identidade-editor.md
  - docs/plan/editor-ui-redesign-light.md
  - docs/plan/text-overlays/00-indice.md
---

# Flow: App de Exemplo (Editor)

> **Resumo:** O app em `example/` é um editor de vídeo em tema claro que consome o plugin: preview em `Texture`, toolbar única (playback, ações de edição, texto, undo/redo, zoom e export), timeline com cabeçalhos de faixa fixos à esquerda, edição por gesto e export para a galeria.

## Visão Geral

`main.dart` monta `TimelineEditorApp` (um `MaterialApp` com `editorTheme` claro) e abre `EditorScreen(autoLoad: true)`. A tela cria um `EditorController` no `initState` e, no primeiro frame, chama `loadSample()`.

`EditorController` é um `ChangeNotifier` — não há Cubit, GetIt nem router aqui. Ele é o único ponto que fala com `NativeTimelinePlayer` e concentra: lista local de clipes (`_clips`), trilha de áudio, lista de text overlays (`_textOverlays`) com seleção, `textureId`, clipe selecionado, aspect ratio e `baseWidth`, zoom da timeline (`pixelsPerSecond`), estados de `loading`/`exporting`/`error`, cache de requisições de thumbnail, throttle de seek e um par de pilhas de undo/redo espelhando o histórico nativo. Desde as correções de fluxo, ele também controla o `EditorMediaSessionService` (importação das mídias do picker para Application Support) e a guarda de geração de load (`_loadGeneration`), que descarta carregamentos tardios após o `dispose`.

O `build` da `EditorScreen` combina dois níveis de reatividade: um `AnimatedBuilder` no controller (mudanças de estado do app) e, dentro dele, um `StreamBuilder<TimelinePlayerState>` no `controller.stateStream` (posição e estado de playback vindos do nativo), com `TimelinePlayerState.initial()` como `initialData`. Erros do stream — inclusive o `playback_error` que o Android empurra pelo `EventChannel` — são capturados por `_capturePlaybackError` e exibidos como SnackBar (padrão `_maybeShowStatusMessage`: erros e mensagens de export são resolvidos por sentinel e limpos com `clearError`/`clearExportMessage`).

A tela é uma `Column`: `EditorTopBar` (reset, menu de origem da timeline e resolução 720p/1080p), `PreviewArea` (`Texture` + pan/crop por arrasto + ghost de texto arrastável), `EditorToolbar` (play circular + tempo, dividir/velocidade/duração (imagens)/proporção/texto/excluir, undo/redo, slider de zoom e export com percentual — rolável horizontalmente em telas estreitas), `TimelineSection` (coluna fixa de lane headers + régua, faixa de clipes, faixa de textos, faixa de áudio e playhead em scroll horizontal).

Duas convenções de interação atravessam a UI. A primeira: **scrub usa seek throttled, edição commita no release**. O arrasto do playhead chama `previewSeek`, que enfileira a posição e libera no máximo um seek a cada 33 ms (um por frame da composição); ao soltar, `commitSeek` cancela o timer e faz o seek definitivo. Trim, velocidade, duração de imagem e volume só chamam o nativo no fim do gesto, porque cada um desses comandos reconstrói a composição. A segunda: **a UI mantém um espelho local dos clipes**. Depois de cada mutação bem-sucedida o controller atualiza `_clips` por conta própria (`_splitLocalClip`, `copyWith`, `removeAt`), porque o nativo devolve apenas durações — não a lista de clipes.

O carregamento de mídia tem três origens: os assets do demo (copiados para `systemTemp` porque o nativo só trabalha com paths de arquivo), a galeria via `ImagePicker.pickMultipleMedia` — cada arquivo é primeiro importado por `EditorMediaSessionService` para uma sessão controlada em Application Support (o path temporário do picker pode ser purgado pelo sistema a qualquer momento) e convertido por `timelineClipFromPath`, que infere vídeo/imagem pela extensão — e o áudio via `FilePicker`. Toda troca de timeline passa por `replaceTimeline`, que valida a existência dos arquivos, descarta o player anterior, carrega a nova lista com guarda de geração, reaplica a trilha de áudio se houver e reseta seleção, caches e histórico.

## Passo a Passo

1. **Bootstrap** — `example/lib/main.dart` → `TimelineEditorApp`
   `MaterialApp(theme: editorTheme, home: EditorScreen(autoLoad: true))`.
2. **Criação do controller** — `example/lib/editor/editor_screen.dart` → `initState`
   `EditorController()` e `addPostFrameCallback` → `loadSample()`.
3. **Carga do sample** — `example/lib/editor/editor_controller.dart` → `loadSample` → `_copyAssetToTempFile`
   Copia `assets/clip_a.mp4`, `assets/still.png` e `assets/clip_b.mp4` para `systemTemp/video_ultra_player_example` e monta três `TimelineClip` (vídeo 2 s com `scale: 1.05`, imagem 1600 ms com `scale: 1.3`, vídeo 2 s).
4. **Troca de timeline** — `replaceTimeline(clips, source:, audioTrack:)`
   Incrementa `_loadGeneration`; se `_mediaFilesExist` falhar (clipe ou áudio ausente), define o sentinel `editor_media_unavailable` sem tocar no player. Caso contrário: `_player.dispose()` → `_player.load(clips, config: compositionConfig)` → `setAudioTrack` se houver. Cada `await` é seguido por `_isCurrentLoad(loadGeneration)`; se a geração ficou obsoleta (dispose ou novo load), a textura tardia é descartada imediatamente. No sucesso, guarda `textureId`, `stateStream`, `_clips`, limpa seleção, caches, histórico e erro, e libera os arquivos de sessão que a nova lista não referencia mais (`_releaseOrphanedSessionFiles`).
5. **Origem alternativa** — `EditorTopBar` → `PopupMenuButton` → `loadSample()` / `pickMedia()`
   `pickMedia` usa `ImagePicker.pickMultipleMedia()` (vídeos e imagens); cada `XFile.path` é importado por `EditorMediaSessionService.importFile()` e só o caminho da cópia controlada vira `TimelineClip` via `timelineClipFromPath` (imagens recebem `kDefaultImageClipDuration` de 3 s; vídeos mantêm duração nativa). Em falha de importação, o sentinel `editor_media_import_failed` é definido e os arquivos já importados no lote são liberados.
6. **Reatividade** — `EditorScreen.build` → `AnimatedBuilder` + `StreamBuilder<TimelinePlayerState>`
   `_capturePlaybackError` converte erro do stream em `controller.setPlaybackError`; `_maybeShowStatusMessage` resolve sentinels (`editor_media_unavailable`, `editor_media_import_failed`, `gallery_permission_denied`) e exibe SnackBar, depois `clearError`/`clearExportMessage`.
7. **Preview** — `example/lib/editor/widgets/preview_area.dart`
   `Texture(textureId:)` dentro de `AspectRatio` derivado de `previewAspectRatio` (`null` para `original`); `onPanUpdate` converte a posição local em `x/y` em `[-1, 1]` e chama `controller.setClipAlignment(state.clipIndex, x, y)`. Com texto selecionado, um "ghost" Flutter (`Positioned` + `FractionalTranslation`) segue o dedo via `updateSelectedTextOverlayPosition` (só local) e o `onPanUpdate` de alinhamento de clipe é desativado; no release `commitSelectedTextOverlayPosition` comita a posição. Tap no ghost abre o sheet de edição; tap fora desseleciona.
8. **Playback** — `example/lib/editor/widgets/editor_toolbar.dart` → `controller.playOrPause(state)`
   Se a posição está a menos de 100 ms do fim, dá seek para zero antes do `play` (a timeline nativa não faz loop).
9. **Timeline** — `example/lib/editor/widgets/timeline_section.dart`
   `contentWidth` derivado de `pixelsPerSecond`; `Row` com a coluna fixa de lane headers (`_LaneHeaderColumn`, ~40 px, ícones de filme, texto e áudio fora do scroll) e o scroll horizontal que empilha `TimelineRuler`, `ClipStrip`, `TextTrackRow`, `AudioTrackRow` e `TimelinePlayhead` num `Stack`. Tempo e zoom vivem na `EditorToolbar`, não mais num header interno.
10. **Scrub** — `_startPlayheadDrag` / `_updatePlayheadDrag` / `_endPlayheadDrag`
    Converte pixels em `Duration`, mostra `_dragPosition` localmente e chama `previewSeek` (throttle de 33 ms) e `commitSeek` no fim. Toque na régua vai direto para `commitSeek`.
11. **Faixa de clipes** — `example/lib/editor/widgets/clip_strip.dart`
    Largura de cada tile proporcional à duração resolvida; `InkWell` → `selectClip` (que também faz `seekToClip`); `LongPressDraggable`/`DragTarget` → `moveClip`; `_ClipThumbnailRail` busca thumbnails do clipe.
12. **Trim** — `example/lib/editor/widgets/clip_trim_handles.dart`
    Aparece só no clipe selecionado; ajusta a largura visual durante o arrasto (`onVisualWidthChange`) e chama `controller.trimClip` no release. Imagens não recebem gesto de trim: apenas feedback passivo de seleção (contorno âmbar, bandas laterais `IgnorePointer` e `Semantics(selected: true)`).
13. **Toolbar** — `example/lib/editor/widgets/editor_toolbar.dart`
    Dividir → `controller.split(state)`; Velocidade → `showSpeedSheet` (slider 0.5–2.0 + chips, commit em `onChangeEnd`); Duração (só com clip de imagem selecionado) → `showImageDurationSheet` (slider 1–15 s, commit em `onChangeEnd` → `setSelectedClipImageDuration` via `replaceClip`); Proporção → `showAspectRatioSheet`; Texto → `controller.addTextOverlay()` (overlay default "Texto" na posição atual de playback, janela de 3 s) + `showTextEditSheet`; Excluir → `removeSelected` (só com mais de um clipe).
14. **Áudio** — `example/lib/editor/widgets/audio_track_row.dart`
    Vazio → `addAudioTrack` (`FilePicker` com extensões de áudio); ativo → slider de volume (`setAudioVolumePreview` no arrasto, `commitAudioVolume` no release) e remover.
15. **Textos** — `example/lib/editor/widgets/text_track_row.dart` + `text_edit_sheet.dart`
    Faixa vazia → "Adicionar texto"; com overlays, um bloco por overlay posicionado por `start`/`end` na escala de `pixelsPerSecond`, destaque quando selecionado, tap → `selectTextOverlay` + sheet. O sheet edita conteúdo, cor/fundo (swatches), tamanho/opacidade/rotação (sliders), alinhamento (`SegmentedButton`), fonte (dropdown com fallback nativo), janela (`RangeSlider`) e excluir — tudo via `commitTextOverlay` no commit do controle.
16. **Config de saída** — `setAspectRatio` / `setBaseWidth` → `_applyCompositionConfig`
    Alteram `compositionConfig` e chamam `_player.setCompositionConfig(...)`, que muda resolução/proporção **no lugar**: a textura, os clipes, os textos, a trilha de áudio, o histórico nativo e a posição de playback sobrevivem — nada é redecodificado e o preview não pisca. Cliques em rajada coalescem: enquanto uma chamada está em voo, `_configUpdatePending` marca que falta aplicar e só uma chamada final (com o estado mais recente) é emitida.
17. **Export** — `EditorToolbar._ExportButton` → `controller.export`
    Cria `systemTemp/video_ultra_player_example_exports`, chama `exportCurrentTimeline(outputPath:)`, assina `exportProgress` para o percentual, salva na galeria com `Gal.putVideo` e apaga o temporário. Sucesso define o sentinel `gallery_saved`; permissão negada lança `gallery_permission_denied` — ambos resolvidos na `EditorScreen`.
18. **Undo/redo** — `EditorToolbar` → `controller.undo()` / `redo()`
    Habilitados só quando o estado nativo (`state.canUndo/canRedo`) **e** as pilhas locais concordam; o controller chama o nativo e restaura o snapshot local (clipes + textos + seleções).
19. **Encerramento** — `EditorScreen.dispose` → `EditorController.dispose`
    Invalida `_loadGeneration` (qualquer load em andamento será descartado), cancela o timer de seek, a assinatura de estado, dispõe o `NativeTimelinePlayer` e limpa a sessão de mídia (`_mediaSession.clearSession`).

### Caminhos alternativos

- **Picker cancelado:** `pickMedia` encerra o loading e mantém a timeline; `addAudioTrack` retorna sem alterar nada.
- **Falha de importação:** `pickMedia` define `editor_media_import_failed` e libera os arquivos já importados no lote; a tela mostra SnackBar de erro.
- **`PlatformException` no picker:** exibida como SnackBar; código `multiple_request` é ignorado.
- **Mídia desapareceu antes do load:** `replaceTimeline` não toca no player nativo e define `editor_media_unavailable`; a tela orienta o usuário.
- **Load tardio após saída:** `dispose` invalida a geração; se o método nativo concluir depois, a textura é descartada sem emitir estado ou erro.
- **Erro em qualquer operação:** `_setError` preenche `_error` e a `EditorScreen` mostra SnackBar de erro, depois `clearError()`.
- **Erro de playback:** `_capturePlaybackError` formata `PlatformException` (`code` + `message`) e chama `setPlaybackError`, que só registra se não houver erro anterior.
- **Permissão de galeria negada:** `_saveToGallery` lança `gallery_permission_denied`, capturado em `export()` → `_setError`; a tela mostra SnackBar.
- **Timeline vazia:** `ClipStrip` mostra `_EmptyClipStrip` ("Load a sample or choose videos") e a toolbar fica desabilitada.
- **Sem `textureId`:** `PreviewArea` mostra `_PreviewPlaceholder` (spinner durante `loading`, ícone caso contrário).
- **`clipDurations` ainda não reportado:** `resolvedClipDurations` cai em `_fallbackClipDuration`, que calcula a partir de trim/duration dividido por `speed`.
- **Split no fim do clipe:** `split` retorna sem fazer nada quando `localPosition >= duration`.

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| Bootstrap | `example/lib/main.dart` | `TimelineEditorApp`, tema, home |
| Tela | `example/lib/editor/editor_screen.dart` | Composição da coluna, `StreamBuilder`, captura de erro de playback, SnackBars com resolução de sentinels |
| Estado | `example/lib/editor/editor_controller.dart` | Toda a orquestração do plugin, espelho local de clipes/áudio/textos, sessão de mídia, guarda de geração de load, duração de imagem |
| Serviço | `example/lib/editor/media_session/editor_media_session_service.dart` | Contrato `importFile`/`releaseFile`/`clearSession` da mídia do editor |
| Serviço | `example/lib/editor/media_session/editor_media_session_service_impl.dart` | Copia mídias para Application Support, serializa operações, restringe exclusões ao diretório controlado |
| Utilitário | `example/lib/editor/media_clip.dart` | `kDefaultImageClipDuration`, `isVideoPath`, `timelineClipFromPath` |
| Tema | `example/lib/editor/theme/editor_theme.dart` | Paleta clara (`editorAccent` teal, `editorBackground` branco, `editorSurface`, `editorSurfaceHigh`, `editorLine`, `editorTextMuted`, `editorText`) e `editorTheme` light |
| Widget | `example/lib/editor/widgets/editor_top_bar.dart` | Reset, origem da timeline e resolução |
| Widget | `example/lib/editor/widgets/editor_toolbar.dart` | Play circular + tempo, dividir/velocidade/duração/proporção/texto/excluir, undo/redo, slider de zoom e export com progresso (linha única rolável) |
| Widget | `example/lib/editor/widgets/preview_area.dart` | `Texture`, `AspectRatio`, pan/crop por gesto, ghost de texto arrastável, placeholder |
| Widget | `example/lib/editor/widgets/timeline_section.dart` | Layout da timeline, coluna fixa de lane headers, scroll e scrub do playhead |
| Widget | `example/lib/editor/widgets/timeline_ruler.dart`, `timeline_ruler_painter.dart` | Régua de segundos (rótulos `mm:ss` a cada 5 s) e seu `CustomPainter` |
| Widget | `example/lib/editor/widgets/timeline_playhead.dart` | Agulha arrastável (linha fina escura cruzando régua e faixas) |
| Widget | `example/lib/editor/widgets/clip_strip.dart` | Tiles proporcionais, seleção, reordenação, rail de thumbnails |
| Widget | `example/lib/editor/widgets/clip_trim_handles.dart` | Alças de trim do clipe selecionado; feedback passivo de seleção para imagens |
| Widget | `example/lib/editor/widgets/audio_track_row.dart` | Faixa de áudio, volume, remoção |
| Widget | `example/lib/editor/widgets/text_track_row.dart`, `text_edit_sheet.dart` | Faixa de textos na timeline e sheet de edição (conteúdo, estilo, janela, excluir) |
| Widget | `example/lib/editor/widgets/speed_sheet.dart`, `duration_sheet.dart`, `aspect_ratio_sheet.dart` | Bottom sheets de velocidade, duração de imagem e proporção |
| Assets | `example/assets/clip_a.mp4`, `still.png`, `clip_b.mp4` | Mídia do sample (declarada em `example/pubspec.yaml`) |
| Config | `example/pubspec.yaml` | Dependência local no plugin, `image_picker`, `file_picker`, `gal`, `path_provider`, assets |
| Testes | `example/test/widget_test.dart` | Widget test do app de exemplo |
| Testes | `example/test/editor_controller_test.dart` | Files-exist bloqueia load, geração tardia é descartada, duração de imagem com clamp, `pickMedia` importa e libera órfãos |
| Testes | `example/test/editor_media_session_service_impl_test.dart` | Cópia estável, propriedade dos arquivos, limpeza de sessão e de sessões obsoletas |
| Testes | `example/test/text_edit_sheet_test.dart`, `text_track_row_test.dart`, `test_fakes.dart` | Sheet de texto, faixa de textos e player fake in-memory |
| Testes | `example/integration_test/plugin_integration_test.dart` | Teste de integração do exemplo |

## Regras de Negócio Relevantes

- **Assets precisam virar arquivo** — `_copyAssetToTempFile`: o nativo só aceita paths de arquivo, então os assets são gravados em `systemTemp` antes do `load`.
- **Mídia do picker é propriedade da sessão** — `pickMedia` + `EditorMediaSessionServiceImpl`: caminhos temporários do `ImagePicker` são copiados para Application Support (`video_ultra_player_example_editor_sessions`); exclusões só são aceitas dentro do diretório controlado.
- **Imagem recebe 3 s por padrão** — `timelineClipFromPath`: imagens ganham `kDefaultImageClipDuration`; vídeos ficam com duração nativa (`duration: null`).
- **Duração de imagem é clampada em 1–15 s** — `setSelectedClipImageDuration`: ajusta a duração via `replaceClip` com commit no release do slider.
- **Arquivo ausente bloqueia o player nativo** — `replaceTimeline` → `_mediaFilesExist`: clips e áudio são validados antes de `dispose/load`, evitando `ERROR_CODE_IO_FILE_NOT_FOUND`; o sentinel `editor_media_unavailable` é definido.
- **Load tardio não sobrevive à tela** — `_loadGeneration`/`_isCurrentLoad`: `dispose()` invalida a geração e qualquer textura que chegar depois é liberada imediatamente.
- **Troca de timeline sempre dispõe a anterior** — `replaceTimeline` chama `_player.dispose()` antes do novo `load`.
- **Play no fim reinicia** — `playOrPause` faz seek para zero quando falta menos de 100 ms para o fim.
- **Scrub é throttled em 33 ms** — `previewSeek`/`_flushPreviewSeek`; a composição renderiza a 30 fps, então seeks mais frequentes que um por frame só acumulam seeks de tolerância zero que o preview nunca chega a mostrar. `commitSeek` cancela o timer e faz o seek final.
- **Edição commita no release** — trim, velocidade, duração de imagem, volume de áudio e textos só chamam o nativo no fim do gesto, porque cada comando reconstrói a composição (Android) ou re-renderiza a videoComposition (iOS). O ghost do preview atualiza só a cópia local durante o arrasto.
- **`selectClip` também faz seek** — seleciona o índice e chama `seekToClip`.
- **Texto default na posição de playback** — `addTextOverlay` cria "Texto" no centro, `start` na posição atual e `end` = `start + 3 s` (clampado pela duração total quando conhecida).
- **`commitTextOverlay` é a única porta de mutação de texto** — substitui a cópia local e chama `updateTextOverlay`; janela com `end <= start` é corrigida para `start + 1 s` defensivamente.
- **Drag de texto tem prioridade sobre pan/crop** — com texto selecionado o `onPanUpdate` de alinhamento de clipe fica desativado no preview.
- **Excluir exige mais de um clipe** — `removeSelected` retorna se `_clips.length <= 1`.
- **`pixelsPerSecond` entre 44 e 132** — `setPixelsPerSecond` faz clamp; define a escala de toda a timeline.
- **`baseWidth` entre 1 e 4096** — `setBaseWidth` faz clamp; o menu oferece 720 e 1080.
- **Mudar proporção ou resolução NÃO recarrega** — `setAspectRatio`/`setBaseWidth` passam por `_applyCompositionConfig` → `setCompositionConfig`, que reaproveita a composição nativa já carregada. `reload()` continua existindo, mas só para recarregar a mesma timeline de fato.
- **Undo exige acordo entre nativo e local** — a `EditorToolbar` usa `state.canUndo && controller.canUndo`; o controller mantém `_undoSnapshots`/`_redoSnapshots` com limite de 50.
- **Espelho local após cada mutação** — o controller atualiza `_clips` explicitamente (`_splitLocalClip` replica a semântica de trim do nativo, inclusive multiplicando a posição local por `speed`); o mesmo vale para `_textOverlays` (add/commit/remove atualizam a lista local).
- **Snapshots locais incluem textos** — `_EditorSnapshot` guarda `textOverlays` e `selectedTextOverlayId`, então undo/redo da UI restauram a seleção junto com os clipes.
- **Cache de thumbnails invalidado em toda edição** — `_thumbnailRequests.clear()` após trim, split, remove, move, speed, duração e troca de timeline.
- **Export vai para a galeria** — `Gal.requestAccess` + `Gal.putVideo`, e o temporário é apagado; mensagens por sentinel (`gallery_saved`/`gallery_permission_denied`).
- **Mensagens de estado são efêmeras** — a `EditorScreen` mostra SnackBar e limpa com `clearError`/`clearExportMessage`, sem status bar persistente.
- **`_notify` respeita o dispose** — `notifyListeners` só é chamado se `_disposed` for `false`.

## Dependências Externas

- **`video_ultra_player`** — via `path: ../`.
- **`image_picker ^1.2.2`** — `pickMultipleMedia()` (vídeos e imagens).
- **`file_picker ^11.0.2`** — áudio (`mp3`, `aac`, `m4a`, `wav`, `flac`, `ogg`, `opus`).
- **`gal ^2.3.1`** — `requestAccess` e `putVideo`.
- **`path_provider ^2.1.5`** — `getApplicationSupportDirectory()` para a sessão de mídia do editor.
- **Permissões nativas** — `example/ios/Runner/Info.plist` e o manifest do app Android precisam declarar acesso a biblioteca/galeria para os pickers e o `gal`.

## Observações

- Estado é `ChangeNotifier` puro: nenhuma camada de domínio/data, nenhum DI — é um app de demonstração, e as instruções do projeto proíbem recriar aqui a Clean Architecture de app.
- Textos estão hardcoded e misturam português e inglês ("Adicionar audio", "Exportar", "Load a sample or choose videos", "Sample"/"Galeria"); não há l10n.
- O campo `_editBusy` é `final bool _editBusy = false` e o getter `editBusy` sempre devolve `false` — resíduo sem efeito.
- O `_title` é fixo (`'Meu vídeo'`) e `_timelineSource` é registrado mas não exibido em nenhum widget.
- `_dragPosition` vive no `_TimelineSectionState`, então durante o arrasto o playhead se move localmente antes de o estado nativo confirmar — é o que evita o "puxão" do seek assíncrono.
- `AudioTrackRow` desenha a trilha com largura mínima de 220 px: o bloco não representa a duração real do áudio.
- O ghost de texto do preview é uma aproximação Flutter (fonte/tamanho aproximados, opacidade 0.8) — a renderização final é nativa e o commit corrige qualquer divergência.
- Áudio adicionado via `FilePicker` não passa pela sessão de mídia: o path do picker é usado diretamente, como no fluxo de referência do luma_vid.
- A sessão de mídia é limpa apenas no `dispose` do controller ou quando o lote importado falha; sessões órfãs de execuções anteriores são removidas no primeiro import de uma nova execução.

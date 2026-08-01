# Reformulação da UI do Editor (layout do print + tema claro)

> **Objetivo:** Reorganizar a tela do editor de exemplo para o layout do print de referência — preview centralizado em fundo claro, barra de ferramentas única sob o preview e timeline com cabeçalhos de faixa fixos à esquerda — sem alterar nenhuma lógica de edição.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/example-editor-app.md`

## Contexto

O app em `example/` é hoje um editor escuro estilo CapCut com cinco seções empilhadas: `EditorTopBar`, `PreviewArea`, `PlaybackBar` (play/tempo/undo/redo), `TimelineSection` (régua + clipes + áudio + playhead + header com tempo/zoom) e `BottomToolbar` (dividir, velocidade, proporção, excluir). O print de referência mostra um editor claro com toolbar única concentrando playback, ações de edição, undo/redo, zoom e export, e uma timeline cujas faixas têm ícones identificadores fixos à esquerda, fora do scroll horizontal. Toda a lógica (scrub throttled, trim no release, undo/redo, export) já funciona no `EditorController` e não muda.

## Design de Origem

- **Decisão aprovada:** Recomposição dos widgets existentes no layout do print com tema claro (accent teal), sem features novas — sem trilha de título, sem filtros, sem fullscreen.
- **Alternativas descartadas:** Reescrever a timeline do zero — risco de regredir scrub/trim/drag-and-drop sem ganho, pois o print mostra os mesmos elementos.
- **Tipo de mudança:** UI-only

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `example/lib/editor/theme/editor_theme.dart` | editar | Paleta clara (fundo branco, superfícies `#F5F6F8`, texto escuro, accent teal `0xFF2AA79B`) e `editorTheme` light |
| `example/lib/editor/widgets/editor_toolbar.dart` | criar | Barra única: play circular + tempo, ações (dividir/velocidade/proporção/excluir), undo/redo, slider de zoom, export com percentual |
| `example/lib/editor/widgets/editor_top_bar.dart` | editar | Remove o `_ExportButton` (vai para a toolbar); mantém reset, origem e resolução |
| `example/lib/editor/widgets/playback_bar.dart` | remover | Conteúdo absorvido pela `EditorToolbar` |
| `example/lib/editor/widgets/bottom_toolbar.dart` | remover | Conteúdo absorvido pela `EditorToolbar` |
| `example/lib/editor/editor_screen.dart` | editar | Nova ordem: TopBar → Preview (Expanded) → EditorToolbar → TimelineSection → status bar |
| `example/lib/editor/widgets/timeline_section.dart` | editar | Remove header interno; `Row` com coluna fixa de lane headers + scroll horizontal; playhead cruzando régua e faixas |
| `example/lib/editor/widgets/timeline_ruler.dart` / `timeline_ruler_painter.dart` | editar | Cores claras; rótulos `mm:ss` a cada 5 s como no print |
| `example/lib/editor/widgets/timeline_playhead.dart` | editar | Linha vertical fina escura com alça pequena no topo |
| `example/lib/editor/widgets/clip_strip.dart` / `clip_trim_handles.dart` | editar | Cores/bordas para o tema claro; seleção em teal |
| `example/lib/editor/widgets/audio_track_row.dart` | editar | Cores para o tema claro |
| `example/lib/editor/widgets/preview_area.dart` | editar | Ajustes mínimos de cor (placeholder/borda) para o tema claro |
| `example/test/widget_test.dart` | editar | Atualizar para a nova estrutura da tela |
| `docs/flow/example-editor-app.md` | editar | Refletir nova composição da tela e arquivos |

## Fases

### Fase 1 — Tema claro

- [x] Passo 1: Reescrever as constantes de `example/lib/editor/theme/editor_theme.dart`: accent teal `Color(0xFF2AA79B)`, background `Color(0xFFFFFFFF)`, surface `Color(0xFFF5F6F8)`, surfaceHigh `Color(0xFFECEEF1)`, line `Color(0xFFD9DDE3)`, textMuted `Color(0xFF6B7280)`
- [x] Passo 2: Converter `editorTheme` para `Brightness.light` com `ColorScheme.light` (primary teal, surface claro), `scaffoldBackgroundColor` branco, iconTheme/textTheme escuros
- [x] Passo 3: Ajustar `FilledButtonThemeData`/`TextButtonThemeData`/`IconButtonThemeData` para foreground escuro e slider teal
- [x] Verificação: `flutter analyze` na pasta `example/` não reporta novos erros no arquivo de tema (erros de cores nos widgets são esperados até as fases seguintes)

### Fase 2 — EditorToolbar + tela recomposta

- [x] Passo 1: Criar `example/lib/editor/widgets/editor_toolbar.dart` com uma `Row` única: botão play/pause circular preenchido (teal) + texto `mm:ss / mm:ss`; ícones `Icons.call_split`, `Icons.speed`, `Icons.aspect_ratio`, `Icons.delete_outline` com as mesmas regras de habilitação do `BottomToolbar` atual; `Icons.undo`/`Icons.redo` com a regra `state.canUndo && controller.canUndo`; slider de zoom (`−`/`+` com `controller.setPixelsPerSecond`, min/max do controller); botão de export com `StreamBuilder<TimelineExportProgress>` mostrando percentual (lógica movida do `_ExportButton` de `editor_top_bar.dart`)
- [x] Passo 2: Editar `example/lib/editor/widgets/editor_top_bar.dart` removendo `_ExportButton` e seus imports órfãos
- [x] Passo 3: Editar `example/lib/editor/editor_screen.dart`: trocar `PlaybackBar` + `BottomToolbar` pela `EditorToolbar` posicionada entre o preview e a `TimelineSection`; atualizar imports
- [x] Passo 4: Remover `example/lib/editor/widgets/playback_bar.dart` e `example/lib/editor/widgets/bottom_toolbar.dart`
- [x] Verificação: `flutter analyze` limpo; nenhuma referência restante a `PlaybackBar`/`BottomToolbar` (`grep`)

### Fase 3 — Timeline com lane headers e playhead fino

- [x] Passo 1: Editar `example/lib/editor/widgets/timeline_section.dart`: remover `_TimelineHeader` (tempo e zoom agora vivem na `EditorToolbar`); reestruturar o corpo como `Row` com coluna fixa de ~40 px (ícone `Icons.movie_outlined` alinhado à faixa de clipes e `Icons.music_note_outlined` alinhado à faixa de áudio, fora do scroll) + `Expanded` com o `SingleChildScrollView` atual (régua, `ClipStrip`, `AudioTrackRow`); alturas das faixas mantidas (régua 30, clipes 58, áudio 38)
- [x] Passo 2: Aumentar a altura do `TimelinePlayhead` para cruzar régua + faixa de clipes + faixa de áudio; editar `timeline_playhead.dart` para linha fina escura (`Color(0xFF1F2430)`, 1.5 px) com alça triangular/circular pequena no topo
- [x] Passo 3: Editar `timeline_ruler.dart` e `timeline_ruler_painter.dart`: ticks e textos em cinza escuro sobre fundo claro; rótulos em formato `mm:ss` a cada 5 segundos (ex.: `00:00`, `00:05`) em vez de `'${second}s'` por segundo
- [x] Passo 4: Editar `clip_strip.dart`, `clip_trim_handles.dart`, `audio_track_row.dart` e `preview_area.dart`: substituir cores duras de tema escuro (`Colors.white`, `editorSurfaceHigh` escuro, bordas) pelos equivalentes claros; seleção de clipe em teal; placeholder do preview com ícone escuro esmaecido
- [x] Verificação: `flutter analyze` limpo

### Fase 4 — Teste de componente

- [x] Passo 1: Reescrever `example/test/widget_test.dart` para a nova estrutura: com `TimelineEditorApp(autoLoad: false)`, esperar `EditorTopBar` (título 'Meu vídeo', '1080p'), `EditorToolbar` (ícone play `Icons.play_arrow`, texto `00:00 / 00:00`, ícones dividir/velocidade/proporção/excluir, undo/redo desabilitados), placeholder do preview (`Icons.video_library_outlined`) e `TimelineSection` com os ícones de lane (`Icons.movie_outlined`, `Icons.music_note_outlined`)
- [x] Passo 2: Testar que os botões de ação da toolbar iniciam desabilitados sem timeline carregada (ex.: `Icons.call_split` com `onPressed == null`)
- [x] Verificação: `flutter test` passa na pasta `example/` sem subir app/emulador

> Nota de execução: a `EditorToolbar` foi envolvida em `SingleChildScrollView` horizontal (sem `Spacer`) para não estourar em telas estreitas de celular — desvio de layout aprovado pelo bom senso de responsividade, sem mudança de escopo.

### Fase 5 — Atualizar Flow

- [x] Passo 1: Atualizar `docs/flow/example-editor-app.md`: resumo (editor claro com toolbar única e lane headers), passo a passo (itens 7–14: Preview, Playback→EditorToolbar, Timeline, Toolbar), tabela de arquivos (criar/remover/editar conforme este plano) e observações
- [x] Passo 2: Atualizar `generated_at`/`verified_at` do frontmatter
- [x] Verificação: o flow não cita mais `playback_bar.dart` nem `bottom_toolbar.dart` (`grep`)

## Critérios de Sucesso

- [x] Tela com a ordem: top bar enxuta → preview → toolbar única → timeline com lane headers fixos
- [x] Tema claro aplicado em toda a tela, accent teal
- [x] Playhead em linha fina cruzando régua e as duas faixas
- [x] `flutter analyze` limpo (raiz e `example/`)
- [x] Testes de widget passando no harness (`flutter test` em `example/`)
- [ ] (manual — feito pelo usuário) Validação funcional no app: play, scrub, trim, split, undo/redo, zoom, export

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Coluna fixa de lane headers dessincronizar verticalmente das faixas ao mudar alturas | Média | Derivar os offsets dos mesmos valores constantes usados no `Stack` da timeline |
| Cores duras (`Colors.white`) esquecidas em algum widget quebrarem o tema claro | Média | `grep` por `Colors.white`/`editorSurface` em `example/lib/editor/widgets/` ao fim da Fase 3 |
| `widget_test.dart` atual depende de textos da `BottomToolbar` removida | Alta | Fase 4 reescreve o teste contra a nova estrutura |

## Rollback

`git checkout -- example/ docs/flow/example-editor-app.md` restaura todos os arquivos; os arquivos novos (`editor_toolbar.dart`, este plano) podem ser apagados.

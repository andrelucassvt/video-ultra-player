# V2-05 — Editor Shell UI (estrutura visual do example)

> **Objetivo:** Reconstruir o `example/` como o editor do wireframe: top bar (X · "Meu vídeo ▾" · `1080p` · "Exportar ›"), área de preview e o esqueleto/tema que hospeda timeline e toolbar.

## Contexto

O `example/lib/main.dart` atual é uma demo técnica (botões soltos, `SegmentedButton`). O wireframe define um editor CapCut-like com top bar, preview central e controles inferiores. Este plano monta a **casca** e o tema; `v2-06` (timeline) e `v2-07` (toolbar) preenchem o miolo. **UI-only** — sem testes. Reaproveita `NativeTimelinePlayer`, `Texture`, `stateStream`, `exportCurrentTimeline` e o picker já existentes.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `example/lib/main.dart` | editar | Trocar `MaterialApp` para tema escuro do editor; `home: EditorScreen` |
| `example/lib/editor/editor_screen.dart` | criar | Scaffold do editor: `Column`(TopBar, PreviewArea Expanded, TimelineSection, BottomToolbar); detém o `NativeTimelinePlayer`, `StreamBuilder<TimelinePlayerState>`, carregamento de clipes e export |
| `example/lib/editor/editor_controller.dart` | criar | `ChangeNotifier`/controller que encapsula `NativeTimelinePlayer` (load, pick, export, seleção de clipe, busy flags, erro) — fonte única de estado da tela |
| `example/lib/editor/widgets/editor_top_bar.dart` | criar | X (fechar/reset), título "Meu vídeo ▾", label de resolução, botão "Exportar ›" com estado de progresso |
| `example/lib/editor/widgets/preview_area.dart` | criar | `AspectRatio` por proporção + `Texture`; mantém pan/crop (`setClipAlignment`); placeholder de loading/empty |
| `example/lib/editor/theme/editor_theme.dart` | criar | Cores (fundo escuro, amarelo de seleção do wireframe), tipografia, espaçamentos |

## Fases

### Fase 1 — Tema e esqueleto

- [x] Criar `editor_theme.dart` (dark, accent amarelo `~#F5C518` como no wireframe).
- [x] `editor_screen.dart`: `Scaffold` dark com `Column`: TopBar (fixo), `Expanded(PreviewArea)`, placeholder de `TimelineSection`, placeholder de `BottomToolbar`.
- [x] `main.dart`: `MaterialApp(theme: editorTheme, home: EditorScreen())`.
- [x] Verificação: app abre com layout em 3 zonas (top/preview/inferior) no tema escuro.

### Fase 2 — Controller de estado

- [x] `editor_controller.dart`: encapsula `NativeTimelinePlayer`; expõe `clips`, `selectedClipIndex`, `aspectRatio`, `baseWidth/resolução`, `busy/exporting/error`, `state` (do `stateStream`).
- [x] Métodos: `loadSample()`, `pickVideos()`, `export()`, `selectClip(i)`, `setAspectRatio(...)`, `reload()` — movidos do `main.dart` atual, reaproveitando a lógica existente.
- [x] `editor_screen.dart` consome o controller (via `ListenableBuilder` + `StreamBuilder`).
- [x] Verificação: carregar sample e galeria funciona; preview renderiza via `Texture`.

### Fase 3 — Top bar

- [x] `editor_top_bar.dart`: ícone X à esquerda (reset/descartar timeline), título central "Meu vídeo ▾", à direita label de resolução (`1080p`) + "Exportar ›".
- [x] Label de resolução abre menu de `baseWidth` (720p/1080p) → atualiza `TimelineCompositionConfig.baseWidth` e recarrega.
- [x] "Exportar ›" chama `controller.export()`; mostra spinner/percentual durante o export (reusa `exportProgress`).
- [x] Verificação: top bar bate com o wireframe; export dispara e mostra progresso.

### Fase 4 — Preview area

- [x] `preview_area.dart`: `AspectRatio` derivado da proporção atual; `Texture(textureId)`; mantém `GestureDetector` de pan/crop chamando `setClipAlignment` (reaproveita lógica atual).
- [x] Placeholder quando `textureId == null` (loading/empty) no estilo do wireframe (moldura tracejada).
- [x] Verificação: preview ocupa a zona central, respeita a proporção e o pan/crop funciona.

## Critérios de Sucesso

- [x] `example/` abre no visual do editor (top bar + preview + zonas inferiores), tema escuro com accent amarelo.
- [x] Carregar/escolher vídeos, trocar resolução e exportar funcionam pela nova casca.
- [x] Build sem erros; `flutter analyze` limpo.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Refactor grande do `main.dart` quebra fluxo existente | Média | Mover lógica para o controller incrementalmente; manter paridade funcional antes do polish |
| Conflito de edição com `v2-06`/`v2-07` no mesmo `main.dart`/screen | Média | Definir placeholders nomeados (`TimelineSection`, `BottomToolbar`) para os outros planos preencherem em arquivos próprios |

## Rollback

Manter o `main.dart` antigo em git; reverter para o commit anterior restaura a demo técnica.

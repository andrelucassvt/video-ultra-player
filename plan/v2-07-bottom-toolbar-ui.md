# V2-07 — Barra Inferior + Controles de Reprodução (UI)

> **Objetivo:** Implementar a barra de ações (Dividir · Velocidade · Proporção · Excluir) e a linha de controles (play/pause · tempo `00:04 / 00:12` · desfazer/refazer) do wireframe, ligando-as às capacidades já implementadas.

## Contexto

Fecha o editor (wireframe #3, #7, #8, #9). Depende de `v2-01` (velocidade), `v2-04` (undo/redo) e do shell `v2-05`. **UI-only** — sem testes. Dividir/Proporção já têm backend (`splitClip`, `OutputAspectRatio`); este plano só os expõe nos controles do wireframe.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `example/lib/editor/widgets/playback_bar.dart` | criar | Play/pause (`play`/`pause`), tempo `posição / total` formatado, botões desfazer/refazer (`undo`/`redo`, habilitados por `canUndo/canRedo`) |
| `example/lib/editor/widgets/bottom_toolbar.dart` | criar | 4 ações do wireframe: Dividir, Velocidade, Proporção, Excluir, com ícones e labels |
| `example/lib/editor/widgets/speed_sheet.dart` | criar | Bottom sheet/slider de velocidade 0.5×–2× → `setClipSpeed(selectedClipIndex, value)` (commit no release) |
| `example/lib/editor/widgets/aspect_ratio_sheet.dart` | criar | Seletor 9:16 / 1:1 / 16:9 → `setAspectRatio` (reaproveita `OutputAspectRatio`) |
| `example/lib/editor/editor_controller.dart` | editar | `split()` (`splitClip` no playhead), `removeSelected()` (`removeClip`), `setSpeed()`, `setAspectRatio()`, `undo()/redo()` |
| `example/lib/editor/editor_screen.dart` | editar | Inserir `PlaybackBar` e `BottomToolbar` nas zonas reservadas pelo `v2-05` |

## Fases

### Fase 1 — Barra de reprodução

- [x] `playback_bar.dart`: botão play/pause refletindo `state.isPlaying`; tempo `mm:ss / mm:ss` (reusa formatação atual); desfazer/refazer habilitados por `state.canUndo/canRedo` → `controller.undo()/redo()`.
- [x] Inserir acima da timeline na `editor_screen`.
- [ ] Verificação: play/pause, tempo ao vivo e undo/redo funcionam e desabilitam corretamente.

### Fase 2 — Barra de ações (toolbar)

- [x] `bottom_toolbar.dart`: 4 itens (ícone + label) Dividir · Velocidade · Proporção · Excluir, no estilo do wireframe.
- [x] Dividir → `controller.split()` (`splitClip(clipIndex, localPosition)` no playhead); desabilitar quando `localPosition == 0`.
- [x] Excluir → `controller.removeSelected()` (`removeClip`), desabilitado se só há 1 clipe.
- [ ] Verificação: dividir e excluir alteram a timeline e o preview.

### Fase 3 — Velocidade e Proporção

- [x] `speed_sheet.dart`: slider/opções 0.5×–2×; preview vivo opcional; commit `setClipSpeed` no release.
- [x] `aspect_ratio_sheet.dart`: 9:16 / 1:1 / 16:9 → `setAspectRatio` + recarregar preview/`AspectRatio`.
- [x] Ligar ambos aos itens "Velocidade" e "Proporção" da toolbar.
- [ ] Verificação: mudar velocidade reflete na duração/timeline; mudar proporção reformata o preview.

## Critérios de Sucesso

- [x] Linha de controles (play · tempo · undo/redo) e barra de ações (Dividir · Velocidade · Proporção · Excluir) fiéis ao wireframe e funcionais.
- [x] Velocidade usa `v2-01`; undo/redo usa `v2-04`; dividir/excluir/proporção usam APIs existentes.
- [x] Build sem erros; `flutter analyze` limpo.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Ação sem clipe selecionado | Média | Desabilitar itens quando não há seleção/posição válida |
| Conflito de edição no `editor_screen`/controller com `v2-06` | Média | Editar zonas/métodos distintos; rodar após `v2-06` (ver `RUN-ALL`) |

## Rollback

UI isolada; reverter o commit remove as barras e mantém o editor de `v2-05`/`v2-06`.

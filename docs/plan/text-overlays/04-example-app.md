# Text Overlays na Timeline — Parte 4: App Exemplo (Editor de Texto)

> **Objetivo da parte:** O app `example/` permite adicionar vários textos, arrastar no preview, editar conteúdo/estilo/janela de tempo num bottom sheet e remover — tudo com commit-only nas mutações nativas.
> **Plano:** `00-indice.md` (Design de Origem, contrato do modelo, ordem e dependências)
> **Depende de:** partes 2 e 3 concluídas (API nativa funcional nas duas plataformas)

## Contexto

O editor do exemplo é um `ChangeNotifier` (`example/lib/editor/editor_controller.dart`) sem DI/router, com toolbar única, preview em `Texture` e timeline com faixas (clipes + áudio via `audio_track_row.dart`). O padrão de áudio se aplica: o controller mantém uma cópia local do estado (`_audioTrack`) para a UI e envia mutações ao player. Para textos vira uma **lista** local `List<TimelineTextOverlay>` + `selectedTextOverlayId`. Regra de ouro (gotcha Android): comandos de edição só no commit do gesto — durante o arrasto no preview, um "ghost" Flutter segue o dedo; o `updateTextOverlay` vai só no release.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `example/lib/editor/editor_controller.dart` | editar | Estado local dos textos + ações add/update/remove/select/commit |
| `example/lib/editor/widgets/text_edit_sheet.dart` | criar | Bottom sheet de edição (conteúdo, cor, tamanho, fonte, alinhamento, opacidade, rotação, janela, excluir) |
| `example/lib/editor/widgets/text_track_row.dart` | criar | Faixa de textos na timeline (blocos posicionados por start/end, tap seleciona) |
| `example/lib/editor/widgets/preview_area.dart` | editar | Ghost arrastável do texto selecionado sobre a `Texture` |
| `example/lib/editor/widgets/editor_toolbar.dart` | editar | Botão "Texto" |
| `example/lib/editor/widgets/timeline_section.dart` | editar | Encaixar `TextTrackRow` (acima da faixa de áudio) |

## Fases

### Fase 1 — Estado e ações no controller

- [x] Em `editor_controller.dart`, adicionar: `List<TimelineTextOverlay> _textOverlays = []`, `String? _selectedTextOverlayId`, getters (`textOverlays`, `selectedTextOverlay`, `hasSelectedTextOverlay`) e `_textOverlayCounter` para ids (`'text_${_textOverlayCounter++}'`)
- [x] `Future<void> addTextOverlay()`: guarda `_textureId == null`; cria overlay default — texto `"Texto"`, centro `(0.5, 0.5)`, `fontSize: 0.08`, cor branca, `start` = posição atual de playback, `end` = min(start + 3s, totalDuration); chama `_player.addTextOverlay`, adiciona na lista local, seleciona e notifica
- [x] `void selectTextOverlay(String? id)` — só seleção local + notify
- [x] `Future<void> commitTextOverlay(TimelineTextOverlay updated)`: substitui na lista local (por `id`), chama `_player.updateTextOverlay(updated)` e notifica — **única porta de mutação** (garante commit-only)
- [x] `void updateSelectedTextOverlayPosition(double x, double y)` — atualiza **só a cópia local** durante o drag (sem channel); `Future<void> commitSelectedTextOverlayPosition()` — chama `commitTextOverlay` com a posição final
- [x] `Future<void> removeSelectedTextOverlay()`: chama `_player.removeTextOverlay(id)`, remove da lista, limpa seleção, notifica
- [x] Limpar `_textOverlays`/seleção onde o estado da timeline é resetado (mesmo lugar onde `_audioTrack` é limpo/recarregado — ver linhas ~167 e ~731 do controller)
- [x] Verificação: `cd example && flutter analyze` limpo

### Fase 2 — Bottom sheet de edição + botão na toolbar

- [x] Criar `example/lib/editor/widgets/text_edit_sheet.dart` (seguir o estilo de `speed_sheet.dart`/`aspect_ratio_sheet.dart`, tema `editor/theme/editor_theme.dart`):
  - `TextField` para o conteúdo (multi-linha), aplicando via `commitTextOverlay` no submit/Desfocar
  - Linha de cores predefinidas (8–10 swatches) para `color`; toggle de cor de fundo (mesmos swatches + "nenhuma")
  - Sliders com label de valor: tamanho (`fontSize` 0.02–0.30), opacidade (0–1), rotação (−180–180°)
  - `SegmentedButton` de alinhamento (esquerda/centro/direita)
  - Dropdown de fonte: "Padrão" + lista curta de fontes de sistema comuns (`Helvetica`, `Arial`, `Courier`, `Times New Roman` no iOS / `sans-serif`, `serif`, `monospace` no Android — uma lista única de nomes, deixando o nativo fazer fallback)
  - `RangeSlider` para a janela `start`/`end` (0 → totalDuration do estado)
  - Botão "Excluir texto" (vermelho) → `removeSelectedTextOverlay`
  - Todos os controles aplicam via `commitTextOverlay` **no release/commit** (`onChangeEnd` de sliders, seleção de cor/fonte), nunca em `onChanged`
- [x] Em `editor_toolbar.dart`, adicionar ação "Texto" (ícone `Icons.text_fields`) que chama `controller.addTextOverlay()` e abre o sheet do texto recém-criado
- [x] Verificação: `flutter analyze` limpo

### Fase 3 — Drag no preview + faixa na timeline

- [x] Em `preview_area.dart`: envolver a `Texture` num `Stack`; quando `controller.hasSelectedTextOverlay`, posicionar um `Positioned` com `IgnorePointer(false)` + `GestureDetector` mostrando um `Text` "ghost" (mesmo conteúdo/cor/tamanho aproximado, opacidade 0.8) na posição `(x, y)` da cópia local; `onPanUpdate` → `updateSelectedTextOverlayPosition` (local), `onPanEnd` → `commitSelectedTextOverlayPosition()`. Tap no ghost abre o `TextEditSheet`. O drag de alinhamento de clipe existente (`onPanUpdate` do GestureDetector atual) fica **desativado** enquanto houver texto selecionado (prioridade ao texto)
- [x] Criar `text_track_row.dart` (espelhar `audio_track_row.dart`): estado vazio com botão "Adicionar texto"; com textos, um bloco por overlay posicionado por `start/totalDuration` e largura `(end-start)/totalDuration` × largura disponível, cor de destaque quando selecionado, tap → `selectTextOverlay` + abre sheet
- [x] Em `timeline_section.dart`, adicionar o `TextTrackRow` numa faixa acima da de áudio (novas constantes `_textTrackTop`/`_textTrackHeight`, deslocando `_audioTrackTop` conforme necessário) e ajustar a altura total da seção
- [x] Verificação: `flutter analyze` limpo

### Fase 4 — Widget tests (harness existente)

> O example tem `example/test/widget_test.dart` — harness `flutter_test` disponível.

- [x] Criar `example/test/text_edit_sheet_test.dart`: o sheet renderiza campo de texto, swatches, sliders e botão excluir; editar o conteúdo e dar submit chama o callback com o texto novo; "Excluir texto" dispara o callback de remoção
- [x] Criar `example/test/text_track_row_test.dart`: estado vazio mostra "Adicionar texto"; com overlays, renderiza um bloco por overlay; tap num bloco dispara seleção
- [x] Ajustar/substituir `example/test/widget_test.dart` se ele quebrar com as mudanças (é o teste default de counter — remover se não tiver relação com o app)
- [x] Verificação: `cd example && flutter test` verde
- [x] Checkpoint: commit das mudanças da parte + informar o usuário que a parte 4 está concluída e a parte 5 está pronta para execução

## Critérios de Sucesso

- [x] `flutter analyze` limpo no example
- [x] Widget tests novos passando (`cd example && flutter test`)
- [x] Nenhuma mutação nativa em `onChanged`/tick de drag — apenas em commit (auditar chamadas a `commitTextOverlay`)
- [ ] _(manual — feito pelo usuário)_ Adicionar 2+ textos, arrastar, mudar cor/fonte/tamanho, ajustar janela, remover; verificar no preview e no MP4 exportado; undo/redo restaurando textos

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Ghost Flutter diverge do render nativo (posição/tamanho) | Média | Ghost é aproximação temporária durante o drag; o commit re-renderiza nativo — documentar no código |
| Conflito entre drag de texto e drag de alinhamento de clipe | Média | Texto selecionado tem prioridade; tocar fora desseleciona |
| `RangeSlider` de janela com `end <= start` | Baixa | `RangeSlider` garante ordem; controller faz clamp extra no commit |

## Rollback

`git revert` do commit do checkpoint da parte. Mudanças confinadas ao `example/` — o plugin não é tocado.

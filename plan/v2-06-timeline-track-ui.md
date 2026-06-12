# V2-06 — Timeline + Régua + Alças de Trim + Trilha de Áudio (UI)

> **Objetivo:** Construir a seção de timeline do wireframe: régua de segundos com agulha (playhead), faixa de clipes com thumbnails, clipe selecionado com alças de trim, badge de duração e a faixa "Adicionar áudio".

## Contexto

Núcleo visual do editor (wireframe #4, #5, #6). Depende de `v2-02` (thumbnails) e `v2-03` (trilha de áudio) já implementados, e do shell de `v2-05`. **UI-only** — sem testes. A fluidez é crítica aqui: scrub e arrasto de alças usam seek leve com debounce e só commitam a mutação real no fim do gesto.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `example/lib/editor/widgets/timeline_section.dart` | criar | Container da timeline: régua + playhead + faixa de clipes + faixa de áudio; `ScrollController` compartilhado e zoom (px por segundo) |
| `example/lib/editor/widgets/timeline_ruler.dart` | criar | `CustomPaint` da régua de segundos (1s, 2s, …) alinhada ao scroll/zoom |
| `example/lib/editor/widgets/timeline_playhead.dart` | criar | Agulha fixa no centro (ou móvel) sincronizada com `state.globalPosition`; arrasto → `seekTo` throttled |
| `example/lib/editor/widgets/clip_strip.dart` | criar | Lista horizontal de clipes; largura ∝ duração; thumbnails via `generateThumbnails` (placeholder→`Image.file`); seleção; reordenar (`moveClip`) |
| `example/lib/editor/widgets/clip_trim_handles.dart` | criar | Alças "‹ ›" nas bordas do clipe selecionado; arrasto atualiza preview por seek; `onPanEnd` → `trimClip(trimStart/trimEnd)`; badge de duração (ex: "3.0s") |
| `example/lib/editor/widgets/audio_track_row.dart` | criar | Faixa "＋ Adicionar áudio"; ao adicionar (picker de áudio) chama `setAudioTrack`; mostra waveform/placeholder, volume e remover |
| `example/lib/editor/editor_controller.dart` | editar | Estado de zoom/scroll, seleção, cache de thumbnails, `addAudioTrack()/removeAudioTrack()`, helpers de trim/seek throttled |

**Notas de fluidez:**
- Scrub/playhead: `seekTo` com throttle (~1 por frame), commit no `onPanEnd`.
- Alças de trim: durante o arrasto, mover a borda + `seekTo` na nova posição (preview vivo); chamar `trimClip` **só no `onPanEnd`** (evita rebuild Android por tick).
- Thumbnails: gerar sob demanda para o range visível; cachear por `(path, ts, width)`.

## Fases

### Fase 1 — Régua + playhead + scroll/zoom

- [x] `timeline_section.dart`: layout com `SingleChildScrollView` horizontal, `pixelsPerSecond` (zoom), largura total ∝ `state.totalDuration`.
- [x] `timeline_ruler.dart`: `CustomPaint` desenhando marcações de segundo conforme zoom/scroll.
- [x] `timeline_playhead.dart`: agulha sincronizada com `globalPosition`; arrasto → `seekTo` throttled; seek por toque na régua.
- [ ] Verificação: régua e agulha acompanham a reprodução; arrastar a agulha faz seek fluido.

### Fase 2 — Faixa de clipes + thumbnails + seleção

- [x] `clip_strip.dart`: um bloco por clipe, largura ∝ duração; thumbnails do `v2-02` (range visível, placeholder enquanto carrega).
- [x] Selecionar clipe → `controller.selectClip(i)` + `seekToClip(i)`; destaque amarelo do wireframe.
- [x] Reordenar por long-press-drag → `moveClip(from, to)`.
- [ ] Verificação: clipes aparecem com miniaturas, selecionáveis e reordenáveis.

### Fase 3 — Alças de trim + badge

- [x] `clip_trim_handles.dart`: alças nas bordas do clipe selecionado; arrasto atualiza largura + `seekTo` (preview vivo).
- [x] `onPanEnd` → `trimClip(clipIndex, trimStart/trimEnd)`; badge de duração atualizada (ex: "3.0s").
- [ ] Verificação: aparar pelas alças é fluido e a duração final bate com o preview/export.

### Fase 4 — Faixa de áudio

- [x] `audio_track_row.dart`: estado vazio "＋ Adicionar áudio"; picker de áudio (`image_picker`/`file_picker`) → `AudioTrack` → `controller.addAudioTrack`.
- [x] Bloco da trilha com nome, controle de volume e remover (`removeAudioTrack`); posição ∝ `offset`.
- [ ] Verificação: adicionar/remover áudio reflete no preview e fica visível abaixo dos clipes.

## Critérios de Sucesso

- [x] Timeline com régua de segundos, agulha sincronizada, clipes com thumbnails, alças de trim e faixa de áudio — fiel ao wireframe.
- [x] Scrub, trim e reordenação são fluidos (sem rebuild por tick; commit no release).
- [x] Build sem erros; `flutter analyze` limpo.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Jank no arrasto por chamadas nativas excessivas | Alta | Throttle/debounce; commit só no `onPanEnd`; seek leve para preview |
| Sincronizar scroll da régua, clipes e áudio | Média | `ScrollController`/coordenada única (`pixelsPerSecond`) compartilhada |
| Picker de áudio dependente de plataforma | Baixa | Usar `file_picker` para áudio; documentar permissão iOS/Android |

## Rollback

UI isolada na pasta `editor/widgets`; reverter o commit remove a seção e volta ao placeholder do `v2-05`.

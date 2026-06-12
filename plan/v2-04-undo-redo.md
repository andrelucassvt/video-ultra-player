# V2-04 — Desfazer / Refazer

> **Objetivo:** Suportar desfazer/refazer de todas as operações de edição (trim, split, insert, remove, move, replace, velocidade, trilha de áudio) com snapshots nativos do modelo de edição, refletindo no preview e no export.

## Contexto

O wireframe (#3) mostra ícones de desfazer/refazer ao lado do tempo. Hoje não há histórico. **Decisão (overview #1):** **snapshot nativo do edit-model** — o compositor já é stateful; manter pilhas `undo`/`redo` de snapshots (estado completo: lista de clipes + velocidades + trilha de áudio) no nativo é consistente com o preview e mais fluido que replay no Dart. **Último plano de capacidade** porque o snapshot precisa já cobrir velocidade (`v2-01`) e áudio (`v2-03`).

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `lib/src/models/edit_history_state.dart` | criar | `EditHistoryState { bool canUndo; bool canRedo; }` + `fromMap` |
| `lib/video_ultra_player_platform_interface.dart` | editar | `Future<void> undo(int textureId)`, `Future<void> redo(int textureId)`; expor `canUndo/canRedo` no estado emitido (`TimelinePlayerState`) |
| `lib/video_ultra_player_method_channel.dart` | editar | Implementar `undo`/`redo` |
| `lib/src/models/timeline_player_state.dart` | editar | Adicionar `canUndo`/`canRedo` (default false) em `fromMap`/`copyWith`/`==`/`hashCode` |
| `lib/src/native_timeline_player.dart` | editar | `undo()`/`redo()` com `_requireTextureId` |
| `ios/Classes/TimelineEditModel.swift` | criar | Modelo de edição serializável + pilhas `undoStack`/`redoStack`; `pushSnapshot()` antes de cada mutação; `undo()/redo()` restauram e recompõem |
| `ios/Classes/TimelineComposition.swift` / `VideoUltraPlayerPlugin.swift` | editar | Toda mutação (trim/split/insert/remove/move/replace/speed/audio) faz `pushSnapshot` antes; `undo`/`redo` restauram e reconstroem mantendo `textureId`; emitir `canUndo/canRedo` |
| `android/.../TimelineEditModel.kt` | criar | Equivalente Kotlin das pilhas de snapshot |
| `android/.../TimelineCompositionController.kt` / `VideoUltraPlayerPlugin.kt` | editar | Mesmo contrato; `setComposition` após restaurar; emitir `canUndo/canRedo` no `emitState` |
| `test/edit_history_state_test.dart` | criar | `fromMap` |
| `test/timeline_player_state_test.dart` | criar/editar | `canUndo/canRedo` no `fromMap` |
| `test/native_timeline_player_test.dart` | editar | `undo`/`redo` delegam e exigem load |
| `test/video_ultra_player_method_channel_test.dart` | editar | Payloads + parsing de `canUndo/canRedo` |

**Nota de fluidez:** `undo`/`redo` reconstroem a composição uma vez (no clique), não por tick — sem preocupação de debounce. Restaurar deve preservar `textureId` e fazer seek para uma posição válida (clamp).

## Fases

### Fase 1 — Testes (contrato)

- [x] `test/timeline_player_state_test.dart`: `fromMap` lê `canUndo`/`canRedo` (default false).
- [x] `test/edit_history_state_test.dart`: `fromMap`.
- [x] `test/native_timeline_player_test.dart`: `undo()`/`redo()` exigem load e delegam à plataforma.
- [x] `test/video_ultra_player_method_channel_test.dart`: payloads de `undo`/`redo`; estado parseia flags.
- [x] Verificação: falham por método/campo ausente.

### Fase 2 — Contrato Dart

- [x] Adicionar `canUndo/canRedo` a `TimelinePlayerState`.
- [x] Criar `EditHistoryState` (se usado fora do state); exportar models.
- [x] Adicionar `undo`/`redo` ao platform interface + method channel + `NativeTimelinePlayer`.
- [x] Verificação: `flutter test`/`flutter analyze` verdes.

### Fase 3 — Nativo iOS

- [x] `TimelineEditModel.swift`: estado de edição completo (clips + speed + audioTrack) com `snapshot()/restore()`; pilhas `undo`/`redo` (limite ex: 50).
- [x] Instrumentar cada mutação para `pushSnapshot` antes de aplicar e limpar `redoStack`.
- [x] `undo`/`redo`: pop/push entre pilhas, recompor, preservar `textureId`, seek com clamp; emitir `canUndo/canRedo`.
- [ ] Verificação: sequência editar→undo→redo restaura preview e estado corretamente.

### Fase 4 — Nativo Android

- [x] `TimelineEditModel.kt`: equivalente; integrar com `setComposition`.
- [x] Instrumentar mutações; `undo`/`redo` recompõem; emitir flags no `emitState`.
- [ ] Verificação: paridade com iOS; export após undo/redo reflete o estado restaurado.

## Critérios de Sucesso

- [ ] Undo/redo cobre trim, split, insert, remove, move, replace, **velocidade** e **trilha de áudio**.
- [x] `canUndo/canRedo` chegam no `stateStream` e habilitam/desabilitam os botões.
- [x] Export após undo/redo corresponde ao preview.
- [x] `flutter test`/`flutter analyze` verdes.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Snapshot não cobre estado novo (speed/áudio) | Alta | Executar este plano **por último**; checklist de campos cobertos no `TimelineEditModel` |
| Memória das pilhas (snapshots grandes) | Média | Snapshot é só metadados (paths + params), não mídia; limitar tamanho da pilha |
| Posição inválida após restaurar | Média | Clamp do seek à nova `totalDuration`; teste de borda |

## Rollback

Aditivo; remover pilhas e métodos. Sem histórico, mutações continuam funcionando como hoje (sem desfazer).

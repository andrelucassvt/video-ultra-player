# V2 — Instrução de Execução via Subagente (RUN-ALL)

> **Objetivo:** Executar todos os planos `v2-01..v2-07` na ordem correta, um por vez, cada um terminando **verde** antes do próximo começar.

## ⚠️ Regra-mãe: SEQUENCIAL, não paralelo

Os planos de capacidade (`v2-01..v2-04`) editam os **mesmos quatro arquivos compartilhados**:

- `lib/video_ultra_player_platform_interface.dart`
- `lib/video_ultra_player_method_channel.dart`
- `ios/Classes/VideoUltraPlayerPlugin.swift` / `ios/Classes/TimelineComposition.swift`
- `android/.../VideoUltraPlayerPlugin.kt` / `android/.../TimelineCompositionController.kt`

Os planos de UI (`v2-05..v2-07`) editam `example/lib/editor/editor_screen.dart` e `editor_controller.dart` em comum.

**Rodar em paralelo causaria colisões de edição e build quebrado.** Portanto: **um subagente por plano, em série, na ordem abaixo.** Antes de invocar este RUN-ALL, confirme as 3 **Decisões em aberto** do `v2-00-overview.md` (undo/redo, escopo da trilha de áudio, thumbnails).

## Ordem obrigatória

```
1. v2-01-clip-speed        (capacidade — federada)
2. v2-02-clip-thumbnails   (capacidade — federada)
3. v2-03-audio-track       (capacidade — federada)
4. v2-04-undo-redo         (capacidade — federada, POR ÚLTIMO: snapshot cobre speed+áudio)
5. v2-05-editor-shell-ui   (UI — casca + tema + controller)
6. v2-06-timeline-track-ui (UI — depende de v2-02 e v2-03)
7. v2-07-bottom-toolbar-ui (UI — depende de v2-01 e v2-04)
```

Justificativa da ordem: `v2-04` precisa que velocidade (`v2-01`) e áudio (`v2-03`) já existam para o snapshot cobri-los; `v2-06` consome thumbnails (`v2-02`) e trilha de áudio (`v2-03`); `v2-07` consome velocidade (`v2-01`) e undo/redo (`v2-04`); todos os UI dependem da casca de `v2-05`.

## Protocolo por plano (cada subagente)

Para cada plano, na ordem, despachar **um** subagente (`general-purpose`) com a instrução:

1. **Antes de implementar:** invocar a skill `brainstorming` (obrigatória por `.claude/rules/brainstorming.instructions.md`) para a funcionalidade do plano.
2. Ler `plan/v2-00-overview.md` (seções **Fluidez/Performance** e **Decisões em aberto**) e o plano `plan/v2-0X-*.md` específico **por inteiro**.
3. Executar as fases na ordem. Planos de capacidade são **TDD**: escrever/ajustar os testes Dart primeiro (eles devem falhar), depois implementar até passarem.
4. Respeitar o padrão federado: contrato no `platform_interface` → impl no `method_channel` → nativo **iOS e Android** (paridade obrigatória — não entregar só uma plataforma).
5. Aplicar as regras de fluidez: nada de rebuild de composição por tick de arrasto; commit no release; seek leve para preview ao vivo.
6. **Gate de conclusão (verde):** `flutter analyze` sem erros **e** `flutter test` passando. Planos de capacidade também devem compilar nativamente (não deixar Swift/Kotlin quebrado).
7. Reportar: arquivos alterados, novos métodos do contrato, e o que ficou pendente de validação manual em device.

> Marcar os checkboxes `[ ]` → `[x]` no arquivo do plano conforme conclui cada passo, para rastreabilidade.

## Gates entre planos

- Não iniciar o próximo plano enquanto o atual não estiver **verde** (`flutter analyze` + `flutter test`).
- Após cada plano de capacidade, rodar a suíte completa `flutter test` (não só os testes novos) — "ignore os testes atuais" significa **reescrever** os afetados para verde, nunca deixar a suíte vermelha.
- Commit por plano (mensagem `feat(v2): <plano>`), em branch (não direto na `master`), para isolar rollback.

## Validação final (após `v2-07`)

- [x] `flutter analyze` limpo e `flutter test` verde no pacote.
- [ ] `cd example && flutter run -d ios` e `-d android`: editor abre no visual do wireframe.
- [ ] Conferir as 9 funcionalidades do wireframe ponta a ponta (exportar, preview, play/tempo, régua+agulha, trim por alças, áudio, dividir, velocidade, proporção) + desfazer/refazer.
- [ ] Export final reflete exatamente o preview (incluindo velocidade e trilha de áudio).
- [ ] Perguntar ao usuário sobre atualizar/criar os flows (ver `v2-00-overview.md` → "Após a Implementação").

## Como despachar (resumo operacional)

Para o usuário: peça ao Claude "execute o plano vX" um a um, **ou** "execute o RUN-ALL", e o orquestrador deve disparar um subagente por plano em série, respeitando os gates acima. Não disparar múltiplos subagentes simultâneos sobre os arquivos compartilhados.

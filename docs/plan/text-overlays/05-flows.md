# Text Overlays na Timeline — Parte 5: Flows e Documentação

> **Objetivo da parte:** Documentação de flows refletindo a feature de text overlays: flows existentes atualizados + novo `docs/flow/text-overlay.md` + AGENTS.md revisado.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** partes 2, 3 e 4 concluídas (implementação final é a fonte da verdade)

## Contexto

O AGENTS.md manda verificar/atualizar `docs/flow/` quando uma feature muda caminhos documentados, e a skill `flow` é o meio de criar flows individuais. Text overlays tocam 5 flows existentes e introduzem um flow próprio. Além disso, o AGENTS.md lista gotchas e convenções — a imutabilidade de efeitos Media3 agora se aplica também a textos, e o iOS ganhou um segundo padrão de rebuild (só `videoComposition`).

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `docs/flow/api-reference.md` | editar | Catalogar `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` (assinatura Dart, payload, tratamento iOS/Android) |
| `docs/flow/ios-native-layer.md` | editar | `animationTool`/`TextOverlayLayers.swift`, rebuild cirúrgico de videoComposition |
| `docs/flow/android-implementation.md` | editar | `TextOverlay.kt`, `OverlayEffect` por clipe, re-ancoragem de janela |
| `docs/flow/timeline-editing.md` | editar | Snapshot passa a incluir `textOverlays` |
| `docs/flow/timeline-export.md` | editar | Textos entram em `exportCurrentTimeline`; `exportTimeline(clips)` exporta sem textos |
| `docs/flow/example-editor-app.md` | editar | Editor de texto (toolbar, sheet, drag, faixa) |
| `docs/flow/text-overlay.md` | criar | Flow completo da feature (via skill `flow`) |
| `AGENTS.md` | editar | Gotchas novos, se aplicável |

## Fases

### Fase 1 — Atualizar flows existentes

- [ ] `docs/flow/api-reference.md`: adicionar as 3 APIs na seção correspondente, seguindo o formato das entradas de `setAudioTrack` (assinatura Dart → nome no channel → payload → ponto de tratamento iOS → ponto de tratamento Android); atualizar o resumo se necessário
- [ ] `docs/flow/ios-native-layer.md`: documentar que `makeVideoComposition()` anexa `AVVideoCompositionCoreAnimationTool` quando há textos, o papel de `TextOverlayLayers.swift` (fontes, janela via `beginTime`/`duration`), e o padrão de mutação cirúrgica (`applyUpdatedVideoComposition` — snapshot → mutate → re-gerar videoComposition, sem remontar tracks)
- [ ] `docs/flow/android-implementation.md`: documentar `TextOverlayDescriptor`, `TimelineTextOverlay : TextOverlay`, a re-ancoragem de janela por clipe (`textOverlaysForClip`) e a posição do `OverlayEffect` depois do `Presentation` em `effectsFor`
- [ ] `docs/flow/timeline-editing.md`: incluir textos na lista de operações de edição e no conteúdo do snapshot
- [ ] `docs/flow/timeline-export.md`: registrar que `exportCurrentTimeline` queima os textos (mesma regra "export = preview") e que `exportTimeline(clips)` exporta sem textos — paridade com a trilha de áudio
- [ ] `docs/flow/example-editor-app.md`: adicionar o editor de texto (botão na toolbar, `TextEditSheet`, ghost de drag no preview, `TextTrackRow`)
- [ ] Atualizar o frontmatter (`generated_at`/`source_commit`/`verified_at`) de cada flow tocado, no formato já usado
- [ ] Verificação: reler cada arquivo editado e confirmar que caminhos de arquivo citados existem no repositório

### Fase 2 — Novo flow + AGENTS.md

- [ ] Invocar a skill `flow` para gerar `docs/flow/text-overlay.md` mapeando a feature de ponta a ponta (modelo Dart → channel → renderização iOS/Android → mutações/undo-redo → export → UI do exemplo), com regras de negócio: janela `[start, end)` clampada pela timeline, `fontPath` tem precedência sobre `fontFamily`, fallback de fonte nunca falha o load, mutações commit-only, overlay fora de qualquer clipe não renderiza
- [ ] Revisar `AGENTS.md`: adicionar aos **Gotchas** os aprendizados reais encontrados na implementação (ex.: quirk de `beginTime` no CoreAnimationTool se o fallback de keyframe foi necessário; timestamps de overlay relativos ao item no Media3; cache de `Typeface`) — somente o que se confirmou no código final
- [ ] Verificação: `flutter analyze` + `flutter test` + `cd example/android && ./gradlew testDebugUnitTest` verdes (sanidade final do repositório)
- [ ] Checkpoint: commit das mudanças da parte + informar o usuário que o plano completo está concluído e listar o que deve ser testado manualmente

## Critérios de Sucesso

- [ ] Nenhum flow cita caminho inexistente ou comportamento divergente do código final
- [ ] `docs/flow/text-overlay.md` criado via skill `flow` com resumo, passo a passo, arquivos envolvidos e regras de negócio
- [ ] AGENTS.md contém os gotchas confirmados da feature
- [ ] Testes e análise estática verdes
- [ ] _(manual — feito pelo usuário)_ Validação funcional completa no app (iOS e Android)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Documentar comportamento planejado em vez do implementado (drift) | Média | Esta parte executa por último e relê o código final antes de escrever; cada flow citado deve ter o caminho verificado com `grep`/`read` |

## Rollback

`git revert` do commit do checkpoint da parte (somente documentação).

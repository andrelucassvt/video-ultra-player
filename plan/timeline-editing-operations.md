# Edição da Timeline (CapCut-like) — trim, split, insert, remove, move, replace

> **Objetivo:** Transformar o `NativeTimelinePlayer` de "carrega uma lista fixa" para um editor de timeline mutável e não-destrutivo: o app passa a cortar (trim in/out), dividir (split), inserir, remover, reordenar e substituir clipes **sem dar `dispose`/`load` da timeline inteira**, preservando textura e posição de playback.

## Contexto

Hoje (v1.1.0) a única forma de mudar a timeline é montar uma nova `List<TimelineClip>` e chamar `dispose()` + `load()` — isso destrói a textura, reinicia a posição e recria a composição do zero. `TimelineClip` só tem `duration` (corte a partir do início da fonte), sem **in-point** real, e não existe nenhuma operação de edição (split/insert/remove/move). Sem isso o plugin não consegue suportar uma UI de timeline editável estilo CapCut. Este plano adiciona a **camada de mutação incremental** — a base sobre a qual áudio, overlays, velocidade e filtros (os próximos milestones) vão se apoiar.

## Decisões de arquitetura (ler antes de implementar)

1. **Identidade por índice, não por id.** As operações usam `clipIndex`, mantendo consistência com o que já existe (`seekToClip`, `setClipAlignment`). `insert`/`remove`/`split` deslocam os índices seguintes; por isso **toda mutação emite um novo estado** imediatamente (com a contagem e as fronteiras atualizadas) para a UI re-sincronizar.
2. **"Incremental" é no nível da API, não necessariamente in-place no nativo.** O controller nativo mantém uma **lista mutável de descritores** (`[ClipDescriptor]`). Cada operação muta essa lista e **reconstrói a composição preservando o `AVPlayer`/`CompositionPlayer`, a textura e a posição** (via swap de `AVPlayerItem` no iOS e `setComposition(comp, positionMs)` no Android — padrão que o `setClipAlignment` do Android **já usa hoje**). Não trocamos o `textureId`. True in-place edit (`AVMutableComposition.removeTimeRange` etc.) fica como otimização futura — a reconstrução preservando posição entrega o comportamento desejado com paridade iOS/Android garantida.
3. **Trim real com in/out.** `TimelineClip` ganha `trimStart` e `trimEnd`. Duração efetiva de vídeo = `(trimEnd ?? duraçãoDaFonte) - trimStart`. Regra de compatibilidade: se `trimEnd` vier, ele vence; senão, se `duration` vier (vídeo), `trimEnd = trimStart + duration`; senão usa a fonte inteira. Para imagem, `trimStart/trimEnd` são ignorados e `duration` continua mandando.
4. **Split = replace por dois descritores.** `splitClip(index, atLocal)` substitui o clipe `index` por dois clipes da mesma fonte: `[trimStart .. trimStart+atLocal]` e `[trimStart+atLocal .. trimEnd]`, herdando `alignment`/`scale`. Depois reconstrói.
5. **Fronteiras dos clipes viram parte do estado.** Para a UI desenhar a timeline e re-sincronizar após cada edição, o `TimelinePlayerState` passa a carregar `clipDurationsMs` (durações resolvidas por clipe, na ordem atual). Resolve também a lacuna documentada em `plan/package-change-video-ultra-player.md` (Opção B).
6. **Transição por-fronteira → corte seco nas fronteiras editadas (DECIDIDO: 6B).** Hoje o crossfade é **global** — aplicado a *todo par adjacente* a partir de `transitionDurationMs`, via overlap em duas tracks alternadas. Sem tratar isso, `splitClip` faz as duas metades virarem adjacentes e **ganharem crossfade → o corte dissolve em si mesmo** (errado; split tem que ser corte seco). A solução adotada é o **modelo real do CapCut**: a transição deixa de ser global e passa a ser **por fronteira**. `TimelineClip` ganha `transitionToNext` (tipo + duração; default = herda `transitionDurationMs` da config para compatibilidade). `split`/`insert`/`move` definem a fronteira nova como `none` (corte seco). As Fases 4 e 5 constroem os overlaps **por-fronteira** a partir de `transitionToNext`, em vez de uma transição global única. `TimelineCompositionConfig.transitionDurationMs` passa a ser apenas o **default** aplicado às fronteiras que não especificam `transitionToNext`.
7. **Uma única fonte de verdade para o export (BLOQUEANTE).** Hoje `exportTimeline(clips)` reconstrói a partir da lista Dart, **independente** do preview. Como as mutações alteram os **descritores nativos**, após `split`/`trim`/`move` o preview e o MP4 exportado divergem — a menos que o chamador reimplemente as 6 operações em Dart para espelhar a lista. Isso é uma armadilha de contrato (o critério de sucesso "export reflete os cortes" depende disso). **Solução:** adicionar `exportCurrentTimeline()` (sem argumento `clips`) que exporta o **estado nativo editado já carregado**. O `exportTimeline(clips)` legado continua para o caso "exportar sem preview".

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models/timeline_clip.dart` | alterar | Adicionar `trimStart`/`trimEnd` (nullable; guard `trimEnd == null \|\| trimStart == null \|\| trimEnd > trimStart`) + `transitionToNext` (tipo + duração, nullable = herda config), serialização `trimStartMs`/`trimEndMs`/`transitionToNext`, `copyWith`, `==`/`hashCode`. |
| `lib/src/models/timeline_composition_config.dart` | alterar | `transitionDurationMs` vira **default por-fronteira** (doc atualizada); sem mudança de assinatura. |
| `lib/src/models/timeline_player_state.dart` | alterar | Adicionar `clipDurations` (`List<Duration>`) + parse de `clipDurationsMs` em `fromMap`. |
| `lib/video_ultra_player_platform_interface.dart` | alterar | Declarar `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip`, `trimClip` + `exportCurrentTimeline` (todos `UnimplementedError`). |
| `lib/video_ultra_player_method_channel.dart` | alterar | Implementar os 7 métodos novos enviando payloads pelo `MethodChannel`. |
| `lib/src/native_timeline_player.dart` | alterar | Expor os 7 métodos públicos, validar `textureId` carregado e argumentos (índices, posição de split). |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | alterar | Roteadores dos 6 métodos novos para o controller. |
| `ios/Classes/TimelineComposition.swift` | alterar | Lista mutável de descritores; aplicar `trimStart/trimEnd` via `CMTimeRange` ao inserir; helpers `split/insert/remove/move/replace`; recomputar segmentos e `clipDurationsMs`. |
| `android/.../TimelineCompositionController.kt` | alterar | Lista mutável de descritores; `ClippingConfiguration` (start/end) por clipe; helpers de mutação; `setComposition(rebuild, positionMs)` preservando posição; emitir `clipDurationsMs`. |
| `android/.../VideoUltraPlayerPlugin.kt` | alterar | Handlers dos 6 métodos novos com validação de argumentos. |
| `example/lib/main.dart` | alterar | Botões de demo: split no playhead, remover clipe atual, mover ←/→, trim do clipe atual. |
| `test/native_timeline_player_test.dart` | alterar | Cobrir os 6 métodos (delegação, validação, `StateError` antes do load). |
| `test/video_ultra_player_method_channel_test.dart` | alterar | Cobrir payloads dos 6 métodos no channel. |
| `test/timeline_clip_test.dart` | criar | Cobrir serialização/validação de `trimStart/trimEnd` e `splitClip` semântica de duração. |
| `flow/native-timeline-player.md` | alterar | Documentar a nova camada de mutação (estrutural). |

### Contrato dos novos métodos (Dart público)

```dart
Future<void> trimClip(int clipIndex, {Duration? trimStart, Duration? trimEnd});
Future<void> splitClip(int clipIndex, Duration atLocalPosition);
Future<void> insertClip(int atIndex, TimelineClip clip);
Future<void> removeClip(int clipIndex);
Future<void> moveClip(int fromIndex, int toIndex);
Future<void> replaceClip(int clipIndex, TimelineClip clip);

/// Exporta o estado nativo editado já carregado (preview == MP4).
Future<String> exportCurrentTimeline({String? outputPath});
```

## Fases

### Fase 1 — Testes do modelo `TimelineClip` (contrato antes da implementação)

> Os testes vão falhar porque os campos ainda não existem — intencional.

- [ ] Criar `test/timeline_clip_test.dart`.
- [ ] Testar serialização: `toJson()` inclui `trimStartMs` e `trimEndMs` (null quando não informados).
- [ ] Testar validação: `trimStart` negativo lança `AssertionError`; `trimEnd <= trimStart` (quando ambos não-nulos) lança `AssertionError`; ambos nulos é válido (usa fonte inteira).
- [ ] Testar compatibilidade: clipe de vídeo só com `duration` serializa `trimEndMs` derivado (`trimStart + duration`) **ou** mantém `duration` — fixar a regra escolhida na decisão (4) e testá-la explicitamente.
- [ ] Testar `transitionToNext`: serializa quando informado; `null` herda o default da config (validar via payload, sem crossfade próprio).
- [ ] Testar `copyWith` e `==`/`hashCode` cobrindo os campos novos.
- [ ] Verificação: `flutter test test/timeline_clip_test.dart` compila e falha só por campos ausentes, não por sintaxe.

### Fase 2 — Testes da API pública e do method channel

- [ ] Em `test/native_timeline_player_test.dart`: para cada um dos 6 métodos de mutação + `exportCurrentTimeline`, testar que delega para o `VideoUltraPlayerPlatform` fake com os argumentos corretos.
- [ ] Testar que cada método de mutação lança `StateError` se chamado antes do `load`; `exportCurrentTimeline` também exige `load`.
- [ ] Testar validação de argumentos: `splitClip` com `atLocalPosition <= 0` ou `clipIndex < 0` lança `ArgumentError`; `moveClip` com `from == to` é no-op (ou lança — fixar e testar).
- [ ] Em `test/video_ultra_player_method_channel_test.dart`: para cada método, verificar o `MethodCall` (nome + mapa de argumentos, incluindo `textureId`).
- [ ] Verificação: ambos os arquivos compilam e falham apenas por métodos ainda não implementados.

### Fase 3 — Implementação Dart (fazer os testes das Fases 1–2 passarem)

- [ ] `timeline_clip.dart`: adicionar `trimStart`/`trimEnd`, asserts, `toJson`, `copyWith`, `==`/`hashCode`.
- [ ] `timeline_player_state.dart`: adicionar `clipDurations` e parse de `clipDurationsMs`.
- [ ] `video_ultra_player_platform_interface.dart`: declarar os 7 métodos com `UnimplementedError`.
- [ ] `video_ultra_player_method_channel.dart`: implementar os 7 métodos (serializar `TimelineClip` com `toJson()` em `insertClip`/`replaceClip`; `exportCurrentTimeline` reusa o `exportEventChannel` de progresso).
- [ ] `native_timeline_player.dart`: expor os 7 métodos com `_requireTextureId()` e validação de argumentos.
- [ ] Verificação: `flutter test` verde; `flutter analyze` sem erros.

### Fase 4 — Implementação iOS (AVFoundation)

- [ ] `TimelineComposition.swift`: trocar a entrada fixa por uma `var descriptors: [TimelineClipDescriptor]` retida no controller; aplicar `trimStart/trimEnd` como `CMTimeRange` ao inserir cada track.
- [ ] Implementar helpers `insert(at:)`, `remove(at:)`, `move(from:to:)`, `replace(at:)`, `split(at:atLocal:)`, `trim(at:start:end:)` que mutam `descriptors` e chamam um `rebuildPreservingPlayback(positionMs:)`.
- [ ] `rebuildPreservingPlayback`: montar nova `AVMutableComposition` + `AVVideoComposition`/`AVAudioMix`, criar novo `AVPlayerItem`, `replaceCurrentItem`, recriar `AVPlayerItemVideoOutput` da `TimelineTexture`, fazer `seek` para a posição preservada (clampada à nova `totalDuration`).
- [ ] Transição por-fronteira (6B): em `makeVideoComposition`/`makeAudioMix`, construir o overlap de cada fronteira a partir do `transitionToNext` do clipe da esquerda (default = config); `split`/`insert`/`move` setam `none` na fronteira criada → corte seco.
- [ ] `exportCurrentTimeline`: montar `buildExportAsset` a partir dos `descriptors` atuais (não da lista recebida), reaproveitando a mesma `AVVideoComposition`/`AVAudioMix` do preview.
- [ ] `VideoUltraPlayerPlugin.swift`: rotear os 7 métodos para o controller; índice inválido = `FlutterError("invalid_index")`.
- [ ] Emitir `clipDurationsMs` em `emitState` e disparar um `emitState` logo após cada mutação.
- [ ] Verificação: `cd example && flutter run -d ios` — split/remove/move/trim atualizam o preview e a UI sem recriar a textura nem voltar a posição a zero.

### Fase 5 — Implementação Android (Media3)

- [ ] `TimelineCompositionController.kt`: manter `var descriptors: MutableList<TimelineClip>`; aplicar `trimStart/trimEnd` via `MediaItem.ClippingConfiguration` (`setStartPositionMs`/`setEndPositionMs`) no build.
- [ ] Implementar os mesmos helpers de mutação reaproveitando `buildTimelineComposition(descriptors)` + `setComposition(comp, positionMs)` (padrão já usado em `setClipAlignment`), clampando `positionMs` à nova duração.
- [ ] `split` reusa a fonte com dois `ClippingConfiguration` derivados; `insert`/`replace` parseiam o mapa do clipe recebido com `parseTimelineClips`.
- [ ] Transição por-fronteira (6B): montar o `VideoCompositorSettings`/alpha ramp **por-fronteira** a partir de `transitionToNext` (default = config); `none` nas fronteiras criadas por `split`/`insert`/`move`.
- [ ] `exportCurrentTimeline`: criar `TimelineCompositionExporter` a partir dos `descriptors` atuais do controller (não da lista recebida).
- [ ] `VideoUltraPlayerPlugin.kt`: handlers dos 7 métodos com validação (`result.error("invalid_index", ...)`).
- [ ] Emitir `clipDurationsMs` em `emitState` e forçar um emit após cada mutação.
- [ ] Verificação: `cd example && flutter run -d android` — paridade com iOS nas 4 operações; posição preservada.

### Fase 6 — App de exemplo (demonstração das operações)

- [ ] `example/lib/main.dart`: adicionar barra de ações com **Split (no playhead)**, **Remover clipe atual**, **Mover ◀/▶**, **Trim (in/out do clipe atual)**.
- [ ] Usar `state.clipIndex` e `state.localPosition` para alimentar `splitClip(clipIndex, localPosition)`; o botão de export passa a chamar `exportCurrentTimeline()` (estado editado), não `exportTimeline(_clips)`.
- [ ] Verificação: fluxo visual ponta-a-ponta — editar, ver o preview mudar, exportar MP4 que **bate com o preview** (split = corte seco, sem dissolve).

### Fase 7 — Atualizar Flow

- [ ] `flow/native-timeline-player.md`: adicionar seção descrevendo a camada de mutação (lista mutável de descritores, reconstrução preservando posição, `clipDurationsMs` no estado) e os 6 novos comandos no passo de "Commands".
- [ ] Atualizar a tabela "Regras de Negócio" com: índices deslocam após insert/remove/split; mutação preserva textura e posição; `trimEnd` vence sobre `duration`.
- [ ] Verificação: o flow descreve corretamente o caminho de uma operação de edição (Dart → channel → nativo → rebuild → emitState).

## Critérios de Sucesso

- [ ] `trimClip`, `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip` existem na API pública e funcionam em iOS **e** Android.
- [ ] Nenhuma operação troca o `textureId` nem reseta a posição para zero (posição é preservada e clampada).
- [ ] `TimelineClip` suporta in/out reais (`trimStart`/`trimEnd`).
- [ ] Split produz **corte seco** (sem dissolve), conforme decisão (6).
- [ ] `exportCurrentTimeline()` gera um MP4 idêntico ao preview editado (mesma fonte de verdade).
- [ ] `TimelinePlayerState.clipDurations` reflete a timeline atual após cada edição.
- [ ] Build sem erros (`flutter analyze`) e **todos os testes unitários passando** (`flutter test`).

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| **Semântica** — split/insert/move criam fronteira que herda o crossfade global → o corte vira dissolve (saída errada, não cosmético) | Alta | Transição por-fronteira (6B): `transitionToNext` com `none` nas fronteiras criadas. Critério de sucesso testa corte seco. |
| Refatorar transição global → por-fronteira pode regredir o crossfade existente entre clipes não-editados | Média | Default `transitionToNext = config.transitionDurationMs`; teste de regressão: timeline carregada sem editar mantém o mesmo crossfade da v1.1.0. |
| **Divergência preview × export** — mutações alteram descritores nativos, mas `exportTimeline(clips)` reconstrói da lista Dart | Alta | `exportCurrentTimeline()` exporta o estado nativo editado; example usa esse caminho. |
| Reconstruir após cada edição pode "piscar" 1 frame no preview | Média | Reconstruir via o mesmo caminho de `load`; preservar posição com `seek` pós-rebuild; aceitar 1 frame de hitch como trade-off documentado. |
| Custo no iOS de re-gerar imagem→MP4 temporário a cada rebuild | Média | Cachear o MP4 temporário por `path` no controller iOS; só regenerar se a fonte/dimensão mudar. |
| Índices deslocados causam dessincronia na UI | Média | Emitir `emitState` (com `clipDurationsMs`) imediatamente após toda mutação; example sempre relê de `state`. |
| Split em posição fora do range do clipe | Baixa | Validar `0 < atLocalPosition < duraçãoEfetiva` no Dart (`ArgumentError`) e clamp defensivo no nativo. |
| Paridade iOS/Android divergir (regra do projeto) | Média | Implementar Fases 4 e 5 na mesma PR; testar as 4 operações nas duas plataformas antes de fechar. |

## Rollback

Mudança aditiva (novos campos opcionais + novos métodos). Para reverter: remover os 6 métodos das 3 camadas Dart e dos handlers nativos, e remover `trimStart`/`trimEnd`/`clipDurations` dos models. O caminho `load`/`exportTimeline` atual continua intacto, então reverter não quebra consumidores da v1.1.0.

## Observações de processo

- A regra do projeto (`.claude/rules/brainstorming.instructions.md`) exige rodar a skill `brainstorming` **antes de iniciar a implementação** — o início da execução deste plano deve passar por ela.
- Paridade iOS/Android faz parte do contrato: não fechar o milestone com só uma plataforma.
- **Futuro:** identidade por índice serve aqui, mas seleção persistente e undo/redo vão exigir um `id` estável por clipe (índice quebra ao mover/inserir). Deixar previsto no modelo quando esses milestones chegarem.

# Core nativo C++ — Parte 3: Benchmark e go/no-go

> **Objetivo da parte:** Medir o protótipo com números comparáveis às metas do índice: métricas coletadas no core, cenários automáticos numa tela de benchmark no app de exemplo e um relatório JSON que o usuário roda no aparelho e registra aqui para decidir o go/no-go.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 2 concluída

## Contexto

A parte 2 entregou o pipeline zero-copy funcionando. Sem métricas, o go/no-go viraria impressão subjetiva. Esta parte instrumenta o core (tempo por quadro, quadros perdidos, latência de seek, recursos vivos, estado térmico, nome do codec), cria cenários repetíveis no example e gera um relatório que o usuário cola no fim deste arquivo. A medição em si é manual e exige o aparelho (Exynos 850 / Galaxy A14); o código fica pronto antes.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `src/core/metrics.hpp/.cpp` | criar | `MetricsAccumulator`: janela circular de amostras, p50/p95/max, taxa de perda |
| `src/tests/metrics_test.cpp` | criar | Percentis, perda de quadro, reset |
| `src/platform/android/bench_session.cpp` | alterar | Alimentar métricas: intervalo entre apresentações, quadros descartados por atraso, latência seek→primeiro quadro, recursos vivos (`AImage`/`EGLImage`), `AThermal_getCurrentThermalStatus` (API 30+, guardado), nomes dos codecs |
| `src/include/vup_core.h` | alterar | `vup_bench_stats` ganha os campos de métrica + `vup_bench_reset_metrics` |
| `lib/src/ffi/core_bench_session.dart` | alterar | `CoreBenchStats` com os campos novos; `resetMetrics()` |
| `lib/src/ffi/core_bench_runner.dart` | criar | Cenários: `playback(60 s)`, `seekSweep(20 seeks pausado)`, `scrub(10 s de seeks a cada 50 ms)`, `soak(10 min)`; produz `CoreBenchReport` (JSON) |
| `test/core_bench_runner_test.dart` | criar | Cenários com `CoreBenchNative` fake e relógio fake |
| `example/lib/core_bench/core_bench_screen.dart` | criar | Escolher 2 vídeos, `Texture`, botões dos cenários, `FrameTiming` da UI, `ProcessInfo.currentRss`, copiar relatório |
| `example/lib/main.dart` | alterar | Acesso à tela de benchmark (entrada secundária, sem tocar no editor) |
| `docs/flow/project-structure.md`, `docs/flow/android-implementation.md` | alterar | Novo layout `src/` + `lib/src/ffi/` e ponte `CoreBenchBridge` |

## Fases

### Fase 1 — Testes (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] `src/tests/metrics_test.cpp`: amostras 1..100 → p50 = 50, p95 = 95, max = 100; janela circular de 600 descarta as mais antigas; `dropRatio` = descartados / (apresentados + descartados); `reset()` zera tudo
- [ ] `test/core_bench_runner_test.dart` (fake + relógio fake): `seekSweep` faz 20 seeks em posições distintas, espera cada um aparecer em `stats.lastSeekLatencyMs` e reporta p95; `playback` chama `resetMetrics`, `play`, aguarda a duração e lê `dropRatio`; relatório serializa em JSON com `deviceModel`, `codecNames`, metas e `passed` por métrica
- [ ] Verificação: `ctest` e `flutter test` falham só nos testes novos, pelos motivos certos

### Fase 2 — Métricas no core

- [ ] Implementar `MetricsAccumulator` (`std::array` fixo, sem alocação por quadro)
- [ ] Em `BenchSession`: registrar intervalo entre swaps, quadros descartados pelo `FrameSelector`, latência do `seek()` até o primeiro swap com o quadro-alvo, contadores de `AImage`/`EGLImage` vivos, estado térmico (`__builtin_available(android 30, *)`, senão `-1`)
- [ ] Estender `vup_bench_stats` (struct C de campos fixos, sem ponteiros) + `vup_bench_reset_metrics`; regenerar bindings com `dart run ffigen`
- [ ] Verificação: `ctest --test-dir build/host` passa e `flutter build apk --debug` compila

### Fase 3 — Cenários em Dart

- [ ] Implementar `CoreBenchRunner` sobre `CoreBenchSession` (relógio injetável para os testes; `Future.delayed` no real)
- [ ] `CoreBenchReport.toJson()` com: modelo do aparelho (via canal, `Build.MODEL` + `Build.SOC_MODEL` em API 31+), nomes dos codecs, cada métrica, meta correspondente do índice e `passed`
- [ ] Verificação: `flutter test` passa

### Fase 4 — Tela de benchmark no example

- [ ] `example/lib/core_bench/core_bench_screen.dart`: seletor de 2 vídeos (o mesmo mecanismo de seleção de mídia já usado pelo editor), `Texture` do `CoreBenchSession`, sliders de posição/largura da camada (`setLayer` no fim do gesto), botões de cada cenário com progresso
- [ ] Medir a UI thread com `SchedulerBinding.instance.addTimingsCallback` (`FrameTiming.buildDuration` + `rasterDuration`, p95) durante o cenário de scrub; RSS com `ProcessInfo.currentRss` a cada 10 s no soak
- [ ] Botão "Copiar relatório" (JSON para a área de transferência) ao fim de cada cenário
- [ ] Entrada em `example/lib/main.dart` sem alterar o fluxo do editor
- [ ] Verificação: `flutter analyze` limpo (raiz e `example/`) e `flutter build apk --release` (em `example/`) compila — medições devem ser feitas em **release**

### Fase 5 — Atualizar Flows e checkpoint

- [ ] `docs/flow/project-structure.md`: pastas `src/` (`core/`, `platform/android/`, `include/`, `tests/`), `lib/src/ffi/`, entrada experimental `video_ultra_player_core_bench.dart`, comando `ctest`
- [ ] `docs/flow/android-implementation.md`: seção curta do `CoreBenchBridge` (canal `video_ultra_player/core`, `SurfaceProducer` → JNI) deixando claro que não substitui o caminho Media3
- [ ] Atualizar a seção **Comandos** do `AGENTS.md` com `cmake -S src -B build/host -DVUP_BUILD_TESTS=ON && cmake --build build/host && ctest --test-dir build/host`
- [ ] Checkpoint: commit das mudanças da parte + resumo curto do que ficou pronto

## Critérios de Sucesso

- [ ] Todas as métricas das metas do índice são produzidas pelo relatório
- [ ] Build release sem erros
- [ ] Todos os testes unitários passando (`ctest`, `flutter test`, `./gradlew testDebugUnitTest`)
- [ ] _(manual — feito pelo usuário)_ Rodar os 4 cenários em **release** no Galaxy A14 (Exynos 850) com dois vídeos 1080p30 e preencher o registro abaixo
- [ ] _(manual — feito pelo usuário)_ Repetir num Snapdragon 680, se disponível

## Registro do go/no-go

_(preenchido pelo usuário com o JSON dos cenários)_

| Aparelho / SoC | Codec | Perda de quadros (60 s) | Seek p95 | UI p95 no scrub | Soak 10 min (RSS / térmico) | Resultado |
|----------------|-------|-------------------------|----------|-----------------|-----------------------------|-----------|
| | | | | | | |

**Decisão:** _go / no-go / go com ressalvas — e o motivo._ Se **go**, abrir o brainstorming da Fase 1 a partir do `00-indice.md`. Se a perda de quadros falhar só com a camada, testar proxy 540p na camada antes de decidir (antecipa a validação da Fase 4).

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Medir em debug distorce tudo (JIT, asserts) | Alta | Critério exige build **release**; o relatório inclui `kReleaseMode` e marca `invalid` se falso |
| Throttling térmico mascara o resultado de outros cenários | Média | Rodar o soak por último; registrar estado térmico no início de cada cenário |
| Vídeos de teste não representativos (bitrate baixo, 720p) | Média | Relatório inclui resolução, fps e bitrate de cada fonte; usar gravações 1080p30 do próprio celular |

## Rollback

Reverter o commit da parte: remove métricas, runner, tela de benchmark e as edições de flow; as partes 1–2 permanecem íntegras.

## Após a Implementação

> Perguntar ao usuário: "Deseja criar um flow do core nativo em `./docs/flow/`? Ele documenta o caminho completo (FFI → sessão → decoder → render → textura) e serve de referência para os planos das próximas fases."

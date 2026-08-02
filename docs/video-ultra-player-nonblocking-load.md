# Plano: Carregamento Nativo Não Bloqueante no `video_ultra_player`

> **Objetivo:** Fazer `NativeTimelinePlayer.load()` preparar mídias e composições fora da thread principal nativa, preservando o contrato Dart e evitando que mídias pesadas congelem a navegação e a interface Flutter.
> **Design de origem:** reconstruído a partir do pedido e da inspeção do `video_ultra_player` 2.1.1
> **Flows relacionados:** `docs/flow/video-edit.md`

## Contexto

O Luma Vid chama `NativeTimelinePlayer.load()` ao abrir o editor. O método Dart já é assíncrono, mas o handler nativo do plugin 2.1.1 executa preparação síncrona antes de devolver o `textureId`. No Android, isso inclui `MediaMetadataRetriever`, resolução das dimensões/durações e montagem da composição Media3. No iOS, a montagem com AVFoundation também é síncrona e clips de imagem são convertidos em MP4 quadro a quadro, incluindo espera por `AVAssetWriter` com semáforo.

Como o processamento começa durante a animação da rota, a tela de seleção ainda pode estar visível quando a thread nativa é bloqueada. O usuário percebe que o toque em “Continuar” travou o app antes de entrar no editor. Este plano deve ser executado no repositório `video-ultra-player`; a cópia em `.pub-cache` serve apenas como referência e nunca deve ser editada.

## Design de Origem

- **Decisão aprovada:** dividir o `load` em duas etapas: preparação pesada em uma fila nativa serial com QoS/prioridade de usuário e instalação curta do player/textura na thread principal. O resultado do MethodChannel continua sendo entregue somente quando o `textureId` estiver pronto.
- **Alternativas descartadas:**
  - *`Isolate.run()`/`compute()` no app Flutter* — o gargalo está depois do MethodChannel, dentro do código Kotlin/Swift; um isolate Dart não muda a thread usada pelo plugin nem deve gerenciar texturas/plugins nativos.
  - *Apenas atrasar `loadClips()` até a animação da rota terminar* — melhora a percepção no app consumidor, mas continua congelando a thread nativa durante o carregamento.
  - *Executar todo o MethodChannel em background* — operações de `TextureRegistry`, `Surface`, `CompositionPlayer`, `AVPlayer` e callbacks Flutter têm requisitos de thread; somente a preparação comprovadamente segura deve sair da thread principal.
  - *Adicionar cancelamento público nesta entrega* — aumentaria o contrato da API sem ser necessário para remover o bloqueio. O descarte tardio existente continua responsável por liberar uma textura cujo consumidor já saiu.
- **Tipo de mudança:** Logic

### Fluxo de threads desejado

```text
Dart UI isolate
    │  MethodChannel: load(clips, config)
    ▼
Thread principal nativa
    │  validar argumentos + enfileirar preparação
    ▼
Fila serial de preparação
    │  metadados + arquivos de imagem + composição preparada
    ▼
Thread principal nativa
    │  registrar textura + criar/conectar player + guardar controller
    ▼
Dart UI isolate
       Future<int> conclui com textureId ou PlatformException
```

### Invariantes

- O contrato público `Future<int> NativeTimelinePlayer.load(...)` não muda.
- `result.success`/`result.error` é chamado exatamente uma vez e na thread principal nativa.
- `controllers` e recursos Flutter de textura continuam sendo criados, acessados e removidos em uma única thread.
- Falha ou descarte durante a preparação remove arquivos temporários e não registra controller/textura órfã.
- A ordem dos clips, duração, áudio, trims, velocidade, aspecto, resolução e overlays permanece idêntica ao comportamento 2.1.1.
- A fila de preparação é serial para evitar múltiplas conversões e leituras pesadas competindo por CPU, disco e memória.

## Arquitetura / Escopo

Os caminhos abaixo são relativos à raiz do repositório `video-ultra-player`, exceto os dois últimos, relativos ao Luma Vid consumidor.

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineLoadPreparer.kt` | criar | Resolver clips, metadados, tamanho de saída e composição imutável fora da main thread |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | modificar | Receber uma timeline já preparada e manter somente criação/controle do player e textura |
| `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | modificar | Enfileirar preparação, voltar à main thread para instalar controller e finalizar o MethodChannel |
| `android/src/test/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPluginTest.kt` | modificar | Contrato de threading, sucesso, erro e callback único do carregamento assíncrono |
| `android/src/test/kotlin/com/andre/video_ultra_player/TimelineLoadPreparerTest.kt` | criar | Parsing e preservação de metadados/configuração da timeline preparada |
| `ios/Classes/TimelineLoadPreparer.swift` | criar | Preparar `TimelineComposition`/`AVPlayerItem` e arquivos temporários fora da main thread |
| `ios/Classes/TimelineComposition.swift` | modificar | Separar preparação pesada da instalação no player e garantir cleanup em falhas |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | modificar | Executar preparer em `DispatchQueue` serial e instalar `TimelinePlayerController` na main queue |
| `example/ios/RunnerTests/RunnerTests.swift` | modificar | Contrato XCTest de fila, callback, erro e preservação da composição |
| `test/native_timeline_player_test.dart` | modificar | Garantir compatibilidade do contrato público e descarte após conclusão tardia |
| `test/video_ultra_player_method_channel_test.dart` | modificar | Garantir propagação assíncrona de `textureId` e `PlatformException` sem mudança do payload |
| `CHANGELOG.md` + `pubspec.yaml` + `ios/video_ultra_player.podspec` | modificar | Registrar correção e publicar nova versão patch do plugin |
| `pubspec.yaml` + locks do Luma Vid | modificar depois da publicação | Consumir a versão corrigida sem editar `.pub-cache` |
| `docs/flow/video-edit.md` do Luma Vid | modificar depois da atualização | Documentar que a preparação do compositor ocorre em background nativo |

## Fases

### Fase 1 — Testes de contrato antes da implementação

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Em `android/src/test/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPluginTest.kt`, injetar um preparer bloqueável e verificar que `onMethodCall("load")` devolve o controle sem esperar a preparação terminar.
- [ ] No mesmo teste Android, capturar as threads e comprovar: preparer fora da main thread; criação/registro do controller e `Result.success` na main thread; callback chamado exatamente uma vez.
- [ ] Criar `android/src/test/kotlin/com/andre/video_ultra_player/TimelineLoadPreparerTest.kt` cobrindo vídeo, imagem, trim, velocidade, duração e `TimelineCompositionConfig`, sem criar player ou textura.
- [ ] Em `example/ios/RunnerTests/RunnerTests.swift`, adicionar fakes injetáveis e expectativas que comprovem preparação fora da main thread, instalação/callback na main thread e retorno imediato do handler.
- [ ] Adicionar testes Android e iOS para exceção durante a preparação: nenhum controller é registrado, temporários são limpos e o Dart recebe `load_failed` uma única vez.
- [ ] Atualizar `test/native_timeline_player_test.dart` e `test/video_ultra_player_method_channel_test.dart` para congelar o contrato atual de payload, `textureId`, erro e conclusão tardia.
- [ ] **Verificação:** testes compilam e falham apenas porque `TimelineLoadPreparer` e as injeções de fila ainda não existem.

### Fase 2 — Pipeline não bloqueante no Android

- [ ] Criar `TimelineLoadPreparer.kt` com `PreparedTimeline`, contendo clips resolvidos, `TimelineRenderSize`, configuração e `Composition`; mover para ele `parseTimelineClips`, `resolveClip`, `MediaMetadataRetriever`, `BitmapFactory.decodeFile`, `outputSizeFor` e a montagem puramente descritiva da composição.
- [ ] Tornar `PreparedTimeline` imutável e impedir que mantenha `MediaMetadataRetriever`, `Bitmap`, `Surface`, `TextureEntry`, `Context` de Activity ou qualquer outro recurso com ciclo de vida/thread affinity.
- [ ] Refatorar `TimelineCompositionController.load()` para instalar um `PreparedTimeline` na main thread: criar `SurfaceTexture`, `Surface`, `CompositionPlayer`, conectar a composição, chamar `prepare()` e iniciar emissão de estado.
- [ ] Em `VideoUltraPlayerPlugin`, criar um executor serial dedicado ao load; no handler, validar/copiar argumentos, executar o preparer no executor e usar `mainHandler.post` para criar/registrar o controller e concluir o `Result`.
- [ ] Proteger detach/falha: invalidar jobs pendentes ao desconectar o engine, não instalar resultado obsoleto, encerrar/recriar corretamente o executor no ciclo do plugin e liberar qualquer recurso preparado.
- [ ] Manter `controllers` e operações posteriores (`play`, `pause`, `seek`, edição, dispose) confinadas à main thread; não converter todo o MethodChannel em background.
- [ ] **Verificação:** `flutter test`, testes JVM/Gradle do plugin e compilação Android passam sem executar example app, emulador ou device.

### Fase 3 — Pipeline não bloqueante no iOS

- [ ] Criar `TimelineLoadPreparer.swift` com fila serial `DispatchQueue(label:qos: .userInitiated)` e um resultado preparado que possua `TimelineComposition` e `AVPlayerItem`, mas não registre textura nem crie `AVPlayer`.
- [ ] Refatorar `TimelineComposition.build` em preparação reutilizável fora da main thread, mantendo ordem, faixas, transforms, duração, áudio e configuração de saída.
- [ ] Executar `UIImage(contentsOfFile:)`, `makeImageVideo`, criação de pixel buffers, loop de frames e `AVAssetWriter.finishWriting` exclusivamente na fila de preparação; remover `Thread.sleep` e `DispatchSemaphore.wait` da main thread.
- [ ] Substituir a espera ocupada do `AVAssetWriterInput` por alimentação assíncrona com `requestMediaDataWhenReady(on:)` e concluir a preparação por callback/`Result`, propagando erro e cleanup.
- [ ] Refatorar `TimelinePlayerController` para receber a composição preparada na main queue e executar somente `TimelineTexture`, `AVPlayer`, registro do `textureId`, observers e início da textura.
- [ ] Em `VideoUltraPlayerPlugin.load`, validar argumentos, despachar preparação, retornar à main queue para instalar o controller e chamar `FlutterResult`; em falha, chamar `composition.dispose()` e mapear para `FlutterError(code: "load_failed")`.
- [ ] Garantir que temporários gerados para imagens sejam removidos em erro, descarte ou resultado obsoleto e que nenhum callback capture fortemente plugin/controller depois do ciclo necessário.
- [ ] **Verificação:** `flutter test`, XCTest `RunnerTests` e build iOS do example passam sem abrir simulador/device.

### Fase 4 — Ciclo de vida, concorrência e observabilidade

- [ ] Serializar solicitações de load por instância do plugin e definir política explícita: requests aceitos concluem na ordem de entrada; dispose de uma textura pronta não interfere em preparação posterior.
- [ ] Adicionar geração/token interno para impedir instalação de resultado depois de detach e garantir que sucesso/erro concorrentes não chamem o mesmo callback duas vezes.
- [ ] Incluir logs de desenvolvimento com tempos separados (`prepare_ms`, `install_ms`, quantidade/tipos de clips), sem paths completos ou dados do usuário; remover logs verbosos da build release quando a convenção do plugin exigir.
- [ ] Adicionar testes de duas solicitações enfileiradas, falha da primeira seguida de sucesso da segunda, detach durante preparação e conclusão tardia após descarte no Dart.
- [ ] Executar `dart format`, formatadores Kotlin/Swift adotados pelo repositório, `flutter analyze`, `flutter test`, testes Android, XCTest e builds nativos sem executar o app.
- [ ] **Verificação:** nenhuma preparação pesada roda na main thread nos testes instrumentados; callbacks permanecem determinísticos e sem vazamento de textura/arquivo temporário.

### Fase 5 — Release e adoção no Luma Vid

- [ ] Atualizar `CHANGELOG.md` explicando que `load()` deixou de bloquear a thread principal durante metadados, composição e conversão de imagens.
- [ ] Incrementar `version` em `pubspec.yaml` e a versão correspondente em `ios/video_ultra_player.podspec`; validar `dart pub publish --dry-run` antes de publicar.
- [ ] Publicar a versão patch e atualizar `video_ultra_player` no `pubspec.yaml` do Luma Vid; regenerar `pubspec.lock` e `ios/Podfile.lock` pelos gerenciadores oficiais.
- [ ] Atualizar `docs/flow/video-edit.md` do Luma Vid: `NativeTimelinePlayer.load()` continua assíncrono, mas a preparação pesada agora ocorre em filas nativas e apenas a instalação curta volta à main thread.
- [ ] Executar `flutter analyze` e `flutter test` no Luma Vid; não rodar app, simulador, emulador, dispositivo ou screenshots nesta etapa automatizada.
- [ ] Entregar ao usuário a validação manual: tocar em “Continuar” com vídeo 4K longo, múltiplos vídeos, imagem de alta resolução e combinação vídeo+imagem em iOS e Android, confirmando transição visível, loading animado e timeline equivalente à versão anterior.
- [ ] **Verificação:** Luma Vid compila contra a versão publicada, testes passam e não há override/path apontando para `.pub-cache`.

## Critérios de Sucesso

- [ ] O handler nativo de `load` apenas valida/enfileira na main thread e devolve o controle sem aguardar metadados ou composição.
- [ ] Metadados, preparação da composição e conversão de imagens executam fora da main thread no Android e iOS.
- [ ] Player, textura, mapas de controllers e callbacks Flutter permanecem na thread principal nativa.
- [ ] O contrato público Dart e o JSON do MethodChannel permanecem compatíveis com 2.1.1.
- [ ] Sucesso e erro concluem exatamente uma vez, sem texturas ou temporários órfãos.
- [ ] Ordem, duração, áudio, trim, velocidade, proporção, resolução, overlays e exportação não sofrem regressão.
- [ ] Build Android e iOS sem erros.
- [ ] Todos os testes Dart, Kotlin e XCTest passando.
- [ ] `flutter analyze` sem novos problemas.
- [ ] _(manual — feito pelo usuário)_ A transição para o editor continua fluida com mídias pesadas e o loading permanece animado até a timeline ficar pronta.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| API nativa ou Media3 exigir acesso na main thread em uma etapa movida | Média | Separar preparação pura/metadata da instalação; manter `TextureRegistry`, `Surface`, players e callbacks na main e adicionar asserts de thread em debug |
| `TimelineComposition`/`AVPlayerItem` atravessar filas com estado mutável | Média | Fazer transferência de propriedade sem uso concorrente; após preparar, somente a main queue passa a acessar a instância |
| Aumento de memória com vários loads/imagens | Média | Fila serial, `autoreleasepool` por frame no iOS, cleanup em todos os caminhos e testes de solicitações enfileiradas |
| Dispose/detach durante job pendente gerar textura ou arquivo órfão | Média | Token de geração, verificação antes da instalação e cleanup do resultado preparado obsoleto |
| Ordem de callbacks mudar em loads concorrentes | Baixa | Executor/fila serial por plugin e testes determinísticos de ordenação |
| Otimização mascarar regressão visual ou de duração | Média | Preservar modelos preparados, ampliar testes de composição e validar manualmente matriz vídeo/imagem nas duas plataformas |

## Rollback

Reverter a versão patch do `video-ultra-player` e restaurar no Luma Vid a versão anterior no `pubspec.yaml`, `pubspec.lock` e `ios/Podfile.lock`. A mudança não altera dados persistidos nem o payload público; portanto, o rollback não exige migração. Não editar nem fixar arquivos diretamente em `.pub-cache`.

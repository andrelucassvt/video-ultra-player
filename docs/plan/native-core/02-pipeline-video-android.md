# Core nativo C++ — Parte 2: Pipeline de vídeo Android

> **Objetivo da parte:** Protótipo Android em que dois vídeos (principal + uma camada posicionada) são decodificados por hardware, compostos em GLES e exibidos numa `Texture` do Flutter, com play/pause/seek — sem passar pela CPU (zero-copy).
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 1 concluída

## Contexto

A parte 1 deixou `libvup_core.so` compilando no host e no APK. Esta parte constrói o caminho que decide a viabilidade do core: `AMediaExtractor` → `AMediaCodec` → `AImageReader` (`AHardwareBuffer`) → `EGLImage` → `GL_TEXTURE_EXTERNAL_OES` → composição → `EGLSurface` sobre o `SurfaceProducer` do Flutter. A lógica de tempo (relógio, escolha de quadro, filtro de seek, transformação da camada) fica em `src/core/`, pura e testada no host; tudo que toca NDK fica em `src/platform/android/`. É um protótipo de benchmark, não a API pública — a sessão real (`load` etc.) é da Fase 1.

### Decisões técnicas fixadas para esta parte

- **Zero-copy:** decoder escreve na `ANativeWindow` de um `AImageReader` (`AIMAGE_FORMAT_PRIVATE`, uso `AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE`, `maxImages = 4`); o render importa o `AHardwareBuffer` via `eglGetNativeClientBufferANDROID` + `eglCreateImageKHR`. Requer API 26+: toda chamada fica atrás de `__builtin_available(android 26, *)` e a sessão reporta erro `unsupported_api` abaixo disso.
- **Decoder em modo síncrono** (`dequeueInputBuffer`/`dequeueOutputBuffer` com timeout de 5 ms) numa thread por fonte — mais simples de depurar que o modo assíncrono; reavaliar na Fase 1.
- **Seek preciso:** `AMediaExtractor_seekTo(..., AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC)` + `AMediaCodec_flush`; decodifica para frente descartando quadros (sem `render`) até o alvo; apresenta o quadro de **maior PTS ≤ alvo**.
- **Relógio:** monotônico de sistema (`CLOCK_MONOTONIC`) — o áudio como relógio mestre entra na Fase 1. Thread de render a 60 Hz (`sleep_until`), apresentando o quadro escolhido pelo `FrameSelector`.
- **Liberação de `AImage`:** a imagem apresentada só é devolvida ao reader depois do `eglSwapBuffers` do quadro seguinte (evita a GPU ler buffer reciclado).
- **Nada bloqueante na thread do Dart:** `vup_bench_open` retorna na hora e abre extractor/codec numa thread do core; o estado (`opening`/`ready`/`error`) é lido por `vup_bench_get_stats`.
- **Camada:** mesma semântica de `TimelineVideoLayer` (`x`, `y` = centro normalizado, `widthFraction`, altura pela proporção da fonte), desenhada por cima da principal; principal em *cover* no canvas.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `src/core/playback_clock.hpp/.cpp` | criar | Relógio play/pause/seek com fonte de tempo injetável (testes) |
| `src/core/frame_selector.hpp/.cpp` | criar | Dado o relógio e a fila de PTS: qual quadro apresentar, quais descartar (atrasados) |
| `src/core/seek_filter.hpp/.cpp` | criar | Após seek, decide descartar/apresentar cada PTS decodificado até o alvo |
| `src/core/layer_transform.hpp/.cpp` | criar | Placement normalizado da camada e *cover* da principal → matriz 4×4 em NDC |
| `src/tests/*_test.cpp` | criar | Testes das quatro unidades acima |
| `src/platform/android/video_decoder.hpp/.cpp` | criar | Extractor + codec + `AImageReader`; thread própria; fila de quadros; seek |
| `src/platform/android/gl_renderer.hpp/.cpp` | criar | EGL/GLES3, import `AHardwareBuffer` → OES, shaders, composição, swap |
| `src/platform/android/bench_session.hpp/.cpp` | criar | Dono de 2 decoders + renderer + relógio + thread de render |
| `src/platform/android/jni_bridge.cpp` | criar | `nativeSetSurface`/`nativeClearSurface` (`ANativeWindow_fromSurface`) |
| `src/include/vup_core.h` | alterar | API C `vup_bench_*` (create/open/play/pause/seek/set_layer/get_stats/destroy) |
| `src/CMakeLists.txt` | alterar | Fontes Android + `mediandk nativewindow EGL GLESv3 android log` |
| `android/src/main/kotlin/com/andre/video_ultra_player/CoreBenchBridge.kt` | criar | `SurfaceProducer` + callbacks + JNI; canal `video_ultra_player/core` |
| `android/.../VideoUltraPlayerPlugin.kt` | alterar | Registrar/desregistrar `CoreBenchBridge` em attach/detach |
| `lib/src/ffi/core_bench_session.dart` | criar | `CoreBenchSession`: FFI + canal; `open/play/pause/seekTo/setLayer/stats/dispose` |
| `lib/video_ultra_player_core_bench.dart` | alterar | Exportar `CoreBenchSession` e `CoreBenchStats` |
| `test/core_bench_session_test.dart` | criar | Payload do canal e ciclo de vida com native fake |

## Fases

### Fase 1 — Testes do host (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] `src/tests/playback_clock_test.cpp`: pausado não avança; `play()` avança com a fonte de tempo fake; `seek(ms)` reposiciona tanto pausado quanto tocando; `pause()` congela a posição exata
- [ ] `src/tests/frame_selector_test.cpp`: fila `[0, 33, 66, 100]` ms com relógio em 70 → apresenta 66 e descarta 0/33; relógio antes do primeiro PTS → não apresenta nada; quadro já apresentado não é reapresentado; fila vazia → nada
- [ ] `src/tests/seek_filter_test.cpp`: alvo 1000 com decodificação `[900, 933, 966, 1000, 1033]` → descarta até 966, apresenta 1000; alvo 1010 → apresenta 1000 (maior PTS ≤ alvo) só quando chega 1033; alvo antes do primeiro quadro → apresenta o primeiro
- [ ] `src/tests/layer_transform_test.cpp`: camada `x=0.5, y=0.5, widthFraction=0.5` com fonte 16:9 num canvas 9:16 → retângulo centrado com largura 50% e altura pela proporção; principal 16:9 em canvas 9:16 em *cover* → escala cobre a altura e corta as laterais
- [ ] Adicionar os novos `.cpp` de teste ao `src/tests/CMakeLists.txt` e os headers vazios em `src/core/`
- [ ] Verificação: `cmake --build build/host` falha na linkagem/asserts pelos motivos certos

### Fase 2 — Unidades puras (fazer os testes passarem)

- [ ] Implementar `PlaybackClock` (`std::function<int64_t()>` como fonte de tempo em µs; default `std::chrono::steady_clock`)
- [ ] Implementar `FrameSelector` e `SeekFilter` sem alocação no caminho quente (operam sobre `std::span<const int64_t>`)
- [ ] Implementar `LayerTransform` devolvendo `std::array<float, 16>` (coluna-maior, pronto para `glUniformMatrix4fv`)
- [ ] Garantir que nenhum arquivo em `src/core/` inclui header do NDK (`grep -rn "android/\|media/\|EGL/\|GLES" src/core` vazio)
- [ ] Verificação: `ctest --test-dir build/host --output-on-failure` passa

### Fase 3 — Decoder Android

- [ ] `VideoDecoder::open(path)`: `AMediaExtractor_setDataSourceFd` (abrir com `open(path, O_RDONLY)`), selecionar a primeira trilha `video/*`, ler largura/altura/rotação/duração do `AMediaFormat`
- [ ] Criar `AImageReader_newWithUsage(w, h, AIMAGE_FORMAT_PRIVATE, AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE, 4)`, obter a `ANativeWindow` e configurar `AMediaCodec_createDecoderByType` com ela; registrar o nome do codec (`AMediaCodec_getName`, API 28+, guardado) para as métricas
- [ ] Thread de decode: loop sync (input do extractor → codec; output com `releaseOutputBuffer(render = SeekFilter decide)`); `AImageReader_setImageListener` empurra `(AImage*, ptsUs)` numa fila limitada (bloqueia o decode quando cheia, sem crescer memória)
- [ ] `seek(targetUs)`: sinaliza a thread, que faz `seekTo(PREVIOUS_SYNC)` + `flush` + ativa o `SeekFilter`; `close()` para a thread, libera `AImage`s pendentes, codec, reader e extractor nessa ordem
- [ ] Verificação: `flutter build apk --debug` (em `example/`) compila sem warnings novos (`-Werror`)

### Fase 4 — Renderer GLES, sessão e API C de benchmark

- [ ] `GlRenderer`: `eglGetDisplay` + contexto ES 3.0 + `eglCreateWindowSurface` sobre a `ANativeWindow` recebida; shader com `samplerExternalOES` (`#extension GL_OES_EGL_image_external_essl3`) e uniform de matriz
- [ ] Import por quadro: `AImage_getHardwareBuffer` → `eglGetNativeClientBufferANDROID` → `eglCreateImageKHR(EGL_NATIVE_BUFFER_ANDROID)` → `glEGLImageTargetTexture2DOES`; destruir o `EGLImage` ao liberar o `AImage`
- [ ] `BenchSession`: abre principal (+ camada opcional) numa thread de trabalho; thread de render a 60 Hz que consulta o relógio, usa `FrameSelector` em cada decoder, desenha principal (*cover*) e camada (`LayerTransform`), faz swap e só então libera as imagens do quadro anterior
- [ ] API C em `vup_core.h`: `vup_bench_create`, `vup_bench_open(h, main_path, layer_path_or_null)`, `vup_bench_set_layer(h, x, y, width_fraction)`, `vup_bench_play`, `vup_bench_pause`, `vup_bench_seek(h, ms)`, `vup_bench_get_stats(h, vup_bench_stats*)` (estado, posição, último erro), `vup_bench_destroy`; nenhuma bloqueia mais que uma troca de mutex
- [ ] Surface ausente (antes do attach ou após `onSurfaceCleanup`): a thread de render continua o relógio mas não desenha; ao receber nova surface recria só a `EGLSurface`
- [ ] Verificação: `ctest` (host) e `flutter build apk --debug` passam

### Fase 5 — Ponte Kotlin/JNI e Dart (testes Dart primeiro)

- [ ] Criar `test/core_bench_session_test.dart` com um `CoreBenchNative` fake e `TestDefaultBinaryMessengerBinding` no canal `video_ultra_player/core`: `open` chama `attachTexture` com `{handle, width, height}` e expõe o `textureId` devolvido; `dispose` chama `detachTexture` e depois `destroy` no native; métodos após `dispose` lançam `StateError`
- [ ] `jni_bridge.cpp`: `Java_com_andre_video_1ultra_1player_CoreBenchBridge_nativeSetSurface(env, cls, jlong handle, jobject surface)` → `ANativeWindow_fromSurface` → `BenchSession::setWindow`; `nativeClearSurface(handle)` → `setWindow(nullptr)` + `ANativeWindow_release`
- [ ] `CoreBenchBridge.kt`: `System.loadLibrary("vup_core")`; `attachTexture` cria `textureRegistry.createSurfaceProducer()`, `setSize(w, h)`, registra `SurfaceProducer.Callback` (`onSurfaceAvailable` → `nativeSetSurface(handle, producer.surface)`; `onSurfaceCleanup` → `nativeClearSurface`) e devolve `producer.id()`; `detachTexture` limpa e `release()`; registrar em `VideoUltraPlayerPlugin.onAttachedToEngine` e liberar tudo em `onDetachedFromEngine`
- [ ] `lib/src/ffi/core_bench_session.dart`: `CoreBenchSession` sobre uma interface `CoreBenchNative` (implementação real via `VupCoreBindings`; o `handle` é o endereço do ponteiro como `int`); `stats()` lê `vup_bench_get_stats` em `CoreBenchStats`; exportar em `lib/video_ultra_player_core_bench.dart`
- [ ] Verificação: `flutter test`, `flutter analyze` e `./gradlew testDebugUnitTest` (em `example/android`) passam

### Fase 6 — Checkpoint

- [ ] Verificação final: `ctest --test-dir build/host`, `flutter test`, `flutter analyze`, `flutter build apk --debug` (em `example/`)
- [ ] Checkpoint: commit das mudanças da parte + resumo curto do que ficou pronto, seguindo direto para a parte 3

## Critérios de Sucesso

- [ ] Lógica de tempo, seek e transformação coberta por testes no host
- [ ] `src/core/` livre de headers de plataforma
- [ ] API C `vup_bench_*` sem chamadas bloqueantes para o Dart
- [ ] Build sem erros
- [ ] Todos os testes unitários passando
- [ ] _(manual — feito pelo usuário)_ No emulador: dois vídeos aparecem compostos na `Texture`, play/pause/seek funcionam, girar a tela / sair e voltar ao app não trava (`onSurfaceCleanup`/`onSurfaceAvailable`)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Decoder do emulador não aceita `AImageReader` `PRIVATE` | Média | Fallback só de depuração para `AIMAGE_FORMAT_YUV_420_888` com upload de planos — marcado como não zero-copy e excluído das métricas |
| Vídeos com rotação (retrato de celular) aparecem deitados | Alta | Ler `rotation-degrees` do `AMediaFormat` e aplicar na matriz da `LayerTransform`; incluir caso no teste |
| GPU lê `AHardwareBuffer` já reciclado (tearing/flicker) | Média | Liberar `AImage` só após o swap seguinte; se persistir, usar `EGL_ANDROID_native_fence_sync` |
| Vazamento de `EGLImage`/`AImage` em seek repetido | Média | Contadores de recursos vivos em `stats` (zerados após `destroy`), conferidos na parte 3 |
| `SurfaceProducer` recriado pelo Impeller em background | Média | Fluxo `onSurfaceCleanup` → `nativeClearSurface` → nova `EGLSurface` no `onSurfaceAvailable` |

## Rollback

Reverter o commit da parte: remove `src/platform/android/`, as unidades em `src/core/`, `CoreBenchBridge.kt`, `CoreBenchSession` e o registro no plugin; a parte 1 permanece íntegra.

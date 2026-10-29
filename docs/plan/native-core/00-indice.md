# Core nativo C++ — Índice

> **Objetivo:** Substituir gradualmente o Media3 (Android) e o AVFoundation (iOS) por um core próprio em C++20 — timeline, render, áudio e export — exposto ao Dart por FFI, começando por um protótipo que decide se o caminho é viável no hardware-piso.
> **Design de origem:** brainstorming desta conversa (aprovado pelo usuário)
> **Flows relacionados:** `docs/flow/project-structure.md`, `docs/flow/android-implementation.md`, `docs/flow/api-reference.md`, `docs/flow/ios-native-layer.md`

## Contexto

O plugin compõe a timeline com `CompositionPlayer`/`Transformer` (Media3) e `AVMutableComposition` (AVFoundation). As limitações dessas APIs — sobretudo o compositor multi-entrada do Media3 — travam o plugin em **1 camada de vídeo**, obrigam a recriar o player a cada edição com camadas, proíbem `seekTo` no player multi-entrada e deixam `crossfade` sem implementação (ver Gotchas do `AGENTS.md`). Um core próprio com um único render graph resolve isso por construção e garante "export = preview" bit a bit nas duas plataformas. O hardware-piso é **Snapdragon 680 / Exynos 850 (Galaxy A14)**, cujo decoder suporta ≈1080p60 de carga total — o que torna proxies obrigatórios para 3+ camadas.

## Design de Origem

- **Decisão aprovada:** Core C++20 próprio (timeline em snapshots imutáveis, render GLES3 no Android / Metal no iOS, áudio como relógio mestre, decode/encode por hardware da plataforma, demux/mux da plataforma — `AMediaExtractor`/`AMediaMuxer`, `AVAssetReader`/`AVAssetWriter`) exposto por **API C** + `ffigen`, compilado via CMake (`externalNativeBuild` no Android, pod no iOS). Convive com o legado **por sessão**: a partir da Fase 1, `load` aceita `TimelineEngine.legacy | core`; `FfiVideoUltraPlayer` implementa `VideoUltraPlayerPlatform` e lança `UnsupportedError` para operações ainda não migradas. O legado continua padrão e com paridade total até a Fase 8.
- **Alternativas descartadas:**
  - Híbrido por função (core na preview, legado no export ou vice-versa) — quebra "export = preview".
  - Troca completa de uma vez — meses sem entrega, risco concentrado.
  - Ordem "paridade primeiro" (camadas por último) — adia a maior trava do produto e a validação de proxies, que muda o modelo de dados.
  - Rust + wgpu — o wgpu não importa texturas externas (`GL_TEXTURE_EXTERNAL_OES`/`CVPixelBuffer`) sem interop `unsafe` do `wgpu-hal`, justamente o caminho zero-copy central de um editor.
- **Tipo de mudança:** Logic
- **Restrições do ambiente:** sem macOS/Xcode e sem aparelho Android físico. A Fase 0 é **Android-only**; nenhum código Swift/ObjC++ do core é escrito antes de haver macOS para compilá-lo. Emulador valida só corretude (decoders são software) — o go/no-go exige aparelho real.

### Estrutura do core no repositório

```
src/
├── CMakeLists.txt          # alvo vup_core (shared lib) + opção VUP_BUILD_TESTS
├── include/vup_core.h      # API C pública (única superfície do ffigen)
├── core/                   # C++20 portável, sem dependência de plataforma (compila no host)
├── platform/android/       # AMediaCodec, AImageReader, EGL/GLES, JNI
└── tests/                  # GoogleTest, roda no host Linux (ctest)
lib/src/ffi/                # bindings gerados + wrappers Dart
```

Regra: `src/core/` nunca inclui header de plataforma — é o que permite testar a lógica no host sem aparelho.

## Roteiro completo

Só a **Fase 0** está detalhada (partes abaixo). Cada fase seguinte recebe brainstorming + plano próprios quando chegar a vez dela, partindo deste índice.

| Fase | Entrega | Funcionalidades atuais cobertas | Status |
|------|---------|--------------------------------|--------|
| **0 — Fundação + protótipo** | Build C++ (host + Android), ponte FFI, decode por hardware → GLES → `Texture`, benchmark e go/no-go | nenhuma da API pública | **detalhada** |
| 1 — Player de sequência | Timeline em snapshot imutável, scheduler, áudio como relógio mestre (Oboe), clipes vídeo/imagem com trim; `TimelineEngine` no `load` | `load`, `play`, `pause`, `seekTo`, `seekToClip`, `setVolume`, `dispose`, `stateStream`, `setCompositionConfig` | a planejar |
| 2 — Edição | Mutações = snapshots novos; undo/redo = pilha de snapshots (testado no host) | `trimClip`, `splitClip`, `insertClip`, `removeClip`, `moveClip`, `replaceClip`, `setClipSpeed`, `setClipAlignment`, `undo`, `redo` | a planejar |
| 3 — Export | Mesmo render graph em relógio offline, encode por hardware + mux, progresso → **primeira versão usável** | `exportTimeline`, `exportCurrentTimeline`, `exportProgress`, `frameRate` | a planejar |
| 4 — Camadas + proxies | N camadas limitadas por orçamento de decoders consultado em runtime, proxies 540p/720p em background, transformação instantânea pausado | `addVideoLayer`, `updateVideoLayer`, `previewVideoLayer`, `removeVideoLayer`; `maxVideoLayers` dinâmico | a planejar |
| 5 — Áudio completo | Mixer com trilhas, offset, trim, fades, volume por clipe/camada | `setAudioTrack`, `removeAudioTrack`, volumes, `extractAudio` | a planejar |
| 6 — Texto e legendas | Rasterização de texto em textura (FreeType+HarfBuzz × texto da plataforma: decidir no brainstorming da fase) | `add/update/removeTextOverlay`, `setCaptions`, `removeCaptions` | a planejar |
| 7 — HDR e qualidade | Tonemap HLG/PQ → SDR em shader, `preserveSourceQuality` | `hdrMode`, `preserveSourceQuality` | a planejar |
| 8 — Core padrão | `engine` default = `core`; legado desligado e depois removido | restante | a planejar |
| — iOS | Backend Metal + VideoToolbox + AudioUnit atrás da mesma API C | todas as fases já concluídas | **bloqueado: requer macOS/Xcode** |

Ficam no legado de propósito: `generateThumbnails` e `renderGrid` (utilitários sem sessão que não sofrem com as limitações do Media3). Depois da paridade: transições (`crossfade`), keyframes, blend modes, efeitos.

## Partes da Fase 0

| # | Arquivo | Entrega | Delegável | Depende de | Status |
|---|---------|---------|-----------|-----------|--------|
| 1 | `01-fundacao-build-ffi.md` | `libvup_core.so` compila no host (testes GoogleTest) e no APK; Dart lê `vup_core_version()` via FFI | não — abre a API C e o layout `src/` consumidos pela parte 2 | — | pendente |
| 2 | `02-pipeline-video-android.md` | Protótipo Android: 2 vídeos decodificados por hardware, compostos em GLES e exibidos numa `Texture` com play/pause/seek | não — decisões de baixo nível (AImageReader/EGL) e verificação final é manual no aparelho | 1 | pendente |
| 3 | `03-benchmark-go-no-go.md` | Métricas no core + tela de benchmark no example + registro do go/no-go | não — o go/no-go é medição manual do usuário no aparelho | 2 | pendente |

## Metas do go/no-go (fecham a Fase 0)

Medidas no **Exynos 850 (Galaxy A14)**; Snapdragon 680 como segundo aparelho desejável:

| Métrica | Meta |
|---------|------|
| Principal 1080p30 + 1 camada 1080p30, compostos | 30 fps estáveis (≤1% quadros perdidos em 60 s) |
| Seek com player pausado → quadro na tela | < 200 ms (p95) |
| UI thread do Flutter durante scrub contínuo | < 16 ms/quadro (p95) |
| 10 min tocando em loop | RSS sem crescimento contínuo; sem queda de fps por throttling térmico |

A meta "3 camadas com proxy 540p" pertence à Fase 4.

## Riscos e Mitigações (globais)

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Sem aparelho físico, a Fase 0 não fecha | Alta | Comprar um Galaxy A14 (Exynos 850) usado antes da parte 3; até lá, partes 1–2 avançam com emulador só para corretude |
| Fragmentação do `AMediaCodec` (bugs por fabricante) | Alta | Testar em 2 SoCs (Samsung + Qualcomm) no go/no-go; registrar nome do codec usado nas métricas |
| Paridade iOS atrasa indefinidamente sem macOS | Alta | Core atrás de `engine` opt-in; legado mantém paridade; `src/core/` portável reduz o backend iOS a decode/render/áudio |
| App maior (`.so` por ABI) | Média | `abiFilters` só `arm64-v8a`, `armeabi-v7a` e `x86_64`; medir tamanho do APK na parte 1 |
| Esforço total muito maior que o previsto | Média | Go/no-go com metas numéricas antes de investir nas Fases 1+ |

## Rollback (global)

O core é aditivo e não é usado pela API pública na Fase 0: reverter os commits das partes remove `src/`, `lib/src/ffi/`, o `externalNativeBuild` e a tela de benchmark sem afetar o legado.

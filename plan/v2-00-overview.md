# V2 — Editor de Timeline CapCut-like (Overview)

> **Objetivo:** Entregar a v2 do `video_ultra_player`: todas as funcionalidades do wireframe (`wireframe.png`) com comunicação Flutter↔nativo fluida, e um `example/` que reproduz o visual do wireframe.

## Contexto

O pacote já tem um compositor nativo único e stateful (iOS `AVMutableComposition`, Android Media3 `CompositionPlayer`) com `load/play/pause/seekTo/seekToClip`, edição (`trimClip/splitClip/insertClip/removeClip/moveClip/replaceClip`), `setVolume`, `setClipAlignment`, proporção (`OutputAspectRatio`) e export real com progresso. O `example/` atual é uma tela de demonstração técnica, não o editor do wireframe. A v2 **reaproveita** todo esse núcleo e adiciona as capacidades que faltam, depois reconstrói a UI do `example/`.

Este documento é o índice. Cada funcionalidade tem um plano próprio em `plan/v2-0X-*.md`. A ordem de execução e as regras para rodar via subagente estão em `plan/v2-RUN-ALL.md`.

## Mapeamento Wireframe → Plano

| # Wireframe | Funcionalidade | Estado atual | Plano |
|---|---|---|---|
| 1 | Exportar (+ label de resolução `1080p`) | ✅ `exportCurrentTimeline`; falta picker de resolução | `v2-05` (UI) + ajuste `baseWidth` |
| 2 | Preview do vídeo | ✅ `Texture` | `v2-05` (UI) |
| 3 | Reproduzir + tempo | ✅ play/pause/tempo | `v2-07` (UI) |
| 3 | Desfazer / Refazer | ❌ ausente | **`v2-04`** |
| 4 | Linha do tempo + agulha | ❌ UI ausente | `v2-06` (UI) |
| 5 | Aparar (trim) com alças | ✅ `trimClip` (backend); alças ausentes | `v2-06` (UI) |
| 6 | Adicionar áudio (trilha) | ❌ ausente | **`v2-03`** |
| 7 | Dividir | ✅ `splitClip`; falta botão | `v2-07` (UI) |
| 8 | Velocidade (0.5×–2×) | ❌ ausente | **`v2-01`** |
| 9 | Proporção (9:16, 1:1, 16:9) | ✅ `OutputAspectRatio` | `v2-07` (UI) |
| — | Thumbnails dos clipes na régua | ❌ ausente (pré-requisito do `v2-06`) | **`v2-02`** |

## Arquitetura (inalterada)

Plugin federado. Toda nova capacidade percorre o mesmo caminho:

```
NativeTimelinePlayer (API pública)
  → VideoUltraPlayerPlatform (contrato abstrato)
    → MethodChannelVideoUltraPlayer (channel video_ultra_player/timeline_player)
      → iOS TimelineComposition/Plugin   +   Android TimelineCompositionController/Plugin
```

Arquivos compartilhados que **quase todos** os planos de capacidade tocam (fonte de conflito — ver `v2-RUN-ALL`):

| Arquivo | Papel |
|---|---|
| `lib/video_ultra_player_platform_interface.dart` | contrato abstrato |
| `lib/video_ultra_player_method_channel.dart` | impl. default via channel |
| `lib/src/native_timeline_player.dart` | API pública + validações |
| `ios/Classes/TimelineComposition.swift` | composição/segmentos iOS |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | dispatch de métodos iOS |
| `android/.../TimelineCompositionController.kt` | composição/estado/export Android |
| `android/.../VideoUltraPlayerPlugin.kt` | dispatch de métodos Android |

## Fluidez / Performance (requisito transversal — todo plano referencia)

"Tudo tem que ser fluido" é requisito de primeira classe. Regras que **todos** os planos de capacidade e UI devem seguir:

1. **Drag não reconstrói composição.** Durante arrasto de alça de trim, playhead ou slider de velocidade, atualize o preview por **seek leve**, nunca por `load`/rebuild. Aplique a mutação real (`trimClip`, `setSpeed`, etc.) **no fim do gesto** (`onPanEnd`/`onChangeEnd`), com debounce/throttle dos updates intermediários (~60–120 ms).
2. **Armadilha Android documentada:** no `flow/native-timeline-player.md`, `setClipAlignment` reconstrói toda a `Composition` Media3 porque efeitos são imutáveis. Qualquer capacidade nova que dependa de efeito (velocidade, trilha de áudio) **não pode** reconstruir por tick de arrasto — só no release. Cada plano afetado tem nota explícita "apply-on-release no Android".
3. **Scrub/seek throttled:** o `seekTo` durante scrub usa o último valor a cada frame, não um por pixel; o commit final usa `onChangeEnd`.
4. **Thumbnails são assíncronos e cacheados** (`v2-02`): nunca bloquear a UI gerando frames; placeholder enquanto carrega.
5. **Estado nativo já é emitido a ~30–33 ms** pelo `EventChannel`; a UI consome via `StreamBuilder`, sem `setState` por pixel.

## Decisões em aberto (confirmar antes do `RUN-ALL`)

Estas três decisões não são determinadas pelo wireframe. Os planos assumem o **default recomendado**; ajuste antes de executar se discordar.

1. **Desfazer/Refazer (`v2-04`) — Default recomendado: snapshot nativo do edit-model.**
   O compositor já é stateful no nativo; manter uma pilha de snapshots do modelo de edição (lista de clipes + trilha de áudio + velocidades) no nativo é consistente e mais fluido que recompor.
   *Alternativa:* replay de comandos no Dart (a API pública guarda o histórico e reaplica). Mais simples no Dart, porém duplica a verdade do estado e tende a divergir do preview. **É a decisão mais cara de errar — é cross-cutting** (precisa cobrir velocidade e áudio), por isso `v2-04` é o último plano de capacidade.

2. **Trilha de áudio (`v2-03`) — Default recomendado: uma trilha de música única**, com `offset` (início na timeline), `volume`, `trim` (in/out) e `fade in/out` opcionais. Cobre "trilha de música / narração" do wireframe.
   *Alternativa:* múltiplas trilhas de áudio sobrepostas. Aumenta muito a superfície nativa; fora do escopo da v2 salvo confirmação.

3. **Thumbnails (`v2-02`) — Default recomendado: extração nativa** (`AVAssetImageGenerator` no iOS, `MediaMetadataRetriever` no Android), cacheada em arquivos por `(path, timestamp)`. Alinha com "toda nova capacidade é federada" e com a fluidez.
   *Alternativa:* pacote Flutter (`video_thumbnail`). Mais rápido de integrar, mas foge do padrão federado e adiciona dependência.

## Ordem de execução (resumo — detalhe em `v2-RUN-ALL`)

```
v2-01 (velocidade) → v2-02 (thumbnails) → v2-03 (áudio) → v2-04 (undo/redo)
   → v2-05 (shell UI) → v2-06 (timeline+track UI) → v2-07 (toolbar UI)
```

Capacidades primeiro (tocam arquivos nativos compartilhados → **serializadas**), depois UI. `v2-04` por último entre as capacidades porque seu snapshot precisa já incluir velocidade e áudio.

## Estratégia de testes (planos de capacidade)

Seguindo "ignore os testes atuais" = **espere reescrever** os testes afetados para que `flutter test` termine **verde** (não deixe a suíte vermelha). Os testes Dart cobrem, espelhando a estrutura atual em `test/`:
- contrato do `VideoUltraPlayerPlatform` (mock da plataforma),
- serialização dos models novos (`toJson`),
- orquestração e validações em `NativeTimelinePlayer`,
- payloads enviados por `MethodChannelVideoUltraPlayer`.

Não cobrem comportamento nativo Swift/Kotlin (fora do alcance de `flutter test`).

## Após a Implementação

> Perguntar ao usuário: "Deseja atualizar o flow em `./flow/native-timeline-player.md` (e criar `./flow/editor-ui.md`) para refletir velocidade, trilha de áudio, undo/redo, thumbnails e a nova UI do editor? Ele documenta o caminho completo do fluxo e serve de referência para futuros planos e revisões."

# Text Overlays na Timeline — Índice

> **Objetivo:** Suportar múltiplos overlays de texto (conteúdo, fonte de sistema ou arquivo custom, cor, tamanho, posição livre, rotação, opacidade e janela `startMs`/`endMs` própria) queimados na composição nativa — idênticos no preview e no MP4 exportado.
> **Design de origem:** brainstorming desta conversa (aprovado pelo usuário)
> **Flows relacionados:** `docs/flow/audio-track-overlay.md` (padrão de referência), `docs/flow/native-timeline-player.md`, `docs/flow/ios-native-layer.md`, `docs/flow/android-implementation.md`, `docs/flow/timeline-editing.md`, `docs/flow/timeline-export.md`, `docs/flow/api-reference.md`

## Contexto

Hoje o plugin compõe clipes de vídeo/imagem em uma única composição nativa com uma trilha de áudio externa opcional, mas não há como sobrepor texto. O usuário quer adicionar vários textos simultâneos, com estilo (fonte/cor/tamanho) e controle total de quando cada um aparece e some. A regra inegociável do projeto é **"export = preview"**: o texto precisa viver no pipeline compartilhado pelas duas operações — `AVVideoCompositionCoreAnimationTool` (CALayer/CATextLayer) dentro de `makeVideoComposition()` no iOS, e `OverlayEffect`/`TextOverlay` (media3-effect, já é dependência) nos efeitos por clipe no Android.

## Design de Origem

- **Decisão aprovada:** Modelo federado espelhando o padrão de `AudioTrack` — `TimelineTextOverlay` com `id` gerado pelo app, mutações `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` nas 4 camadas (platform_interface → method_channel → iOS → Android), lista guardada no estado nativo, entrando no `TimelineEditSnapshot` (undo/redo) e no rebuild que preserva `textureId`/posição. Renderização queimada no vídeo: iOS via `animationTool` na `videoComposition` (rebuild cirúrgico, sem remontar tracks — mesmo padrão de `setClipAlignment`); Android via `OverlayEffect` com `TextOverlay` custom por clipe (rebuild completo, efeitos imutáveis — commit-only).
- **Alternativas descartadas:** (1) Overlay Flutter no preview + nativo só no export — risco de divergência visual, fere "export = preview". (2) API em lote `setTextOverlays(List)` — foge do padrão de mutações do projeto e torna undo/redo grosseiro. (3) Só fontes do sistema — usuário aprovou sistema + arquivo custom (.ttf/.otf via `fontPath`).
- **Tipo de mudança:** Logic

## Modelo de dados (contrato aprovado)

`TimelineTextOverlay` (Dart, serializa em ms no channel):

| Campo | Tipo Dart | Chave no channel | Semântica |
|-------|-----------|------------------|-----------|
| id | `String` (gerado pelo app) | `id` | Identidade para update/remove |
| text | `String` | `text` | Conteúdo (multi-linha via `\n`) |
| start | `Duration` | `startMs` | Início da janela na timeline |
| end | `Duration` | `endMs` | Fim da janela (clamp pela duração total; visível em `[start, end)`) |
| x, y | `double` 0..1 | `x`, `y` | Centro do texto no frame (0,0 = canto superior esquerdo) |
| rotationDegrees | `double` | `rotationDegrees` | Rotação em graus |
| fontSize | `double` (0, 1] | `fontSize` | Fração da altura do vídeo (independente de resolução) |
| color | `int` ARGB | `color` | Cor do texto |
| fontFamily | `String?` | `fontFamily` | Nome de fonte do sistema |
| fontPath | `String?` | `fontPath` | Arquivo .ttf/.otf (precedência sobre `fontFamily`) |
| backgroundColor | `int` ARGB | `backgroundColor` | Cor da caixa de fundo (0/transparente = sem fundo) |
| opacity | `double` 0..1 | `opacity` | Opacidade do overlay |
| textAlign | enum `left/center/right` | `textAlign` | Alinhamento de multi-linha |

API pública (`NativeTimelinePlayer`, todas exigem `load`): `addTextOverlay(overlay)`, `updateTextOverlay(overlay)`, `removeTextOverlay(id)`. Channel: `{textureId, overlay}` / `{textureId, overlayId}`.

## Partes

| # | Arquivo | Entrega | Depende de | Status |
|---|---------|---------|-----------|--------|
| 1 | `01-camada-dart.md` | Modelo + API federada Dart completa e testada (fake platform) | — | concluída |
| 2 | `02-ios-nativo.md` | Textos renderizados no preview e export iOS, com undo/redo | 1 | pendente |
| 3 | `03-android-nativo.md` | Textos renderizados no preview e export Android, com undo/redo + testes Kotlin | 1 | pendente |
| 4 | `04-example-app.md` | Editor de texto completo no app exemplo (adicionar, arrastar, editar, remover) | 2, 3 | pendente |
| 5 | `05-flows.md` | Flows atualizados + novo `text-overlay.md` + AGENTS.md revisado | 2, 3, 4 | pendente |

## Riscos e Mitigações (globais)

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Timestamps de overlay no Media3 são relativos ao item, não à timeline | Alta | Gerar efeitos por clipe com janela ajustada pelo offset do clipe (`startMs - clipStartMs`); função pura testável em unit test |
| `CATextLayer` com `beginTime` fora da janela aparecer no primeiro frame (comportamento conhecido do CoreAnimationTool) | Média | Usar `AVCoreAnimationBeginTimeAtZero` + `fillMode`/opacity keyframe se necessário; validar no teste manual iOS |
| Divergência visual iOS × Android (métricas de fonte, baseline) | Média | Aceitar paridade aproximada de posição/tamanho (âncora = centro do texto); ajustes finos após teste manual do usuário |
| Fonte custom inválida/ausente em runtime | Baixa | Fallback para fonte do sistema nas duas plataformas; nunca falhar o load por causa de fonte |

## Rollback (global)

Cada parte é independente e fecha com o repositório íntegro. Rollback por parte: `git revert` do commit do checkpoint da parte. A feature é aditiva (novos métodos/modelos) — nenhuma API existente muda de assinatura, exceto `TimelineEditSnapshot` (interno nas duas plataformas), então remover a feature é deletar os arquivos/casos novos sem efeito colateral no restante.

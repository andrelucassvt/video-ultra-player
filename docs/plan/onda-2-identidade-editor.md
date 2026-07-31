# Onda 2 — Identidade de Editor (Efeitos, Overlays e Waveform)

> **Objetivo:** Transformar o plugin em um editor visual completo: ajustes de cor por clipe, filtros LUT, fundo desfocado, texto e stickers sobrepostos com intervalo de tempo, e extração de waveform de áudio — com paridade iOS/Android e preview idêntico ao export.
> **Design de origem:** brainstorming desta conversa
> **Flows relacionados:** `docs/flow/native-timeline-player.md`, `docs/flow/ios-native-layer.md`, `docs/flow/android-implementation.md`, `docs/flow/project-structure.md`

## Contexto

Depois da Onda 1 a API cobre o essencial de corte e playback, mas nada de tratamento visual: sem cor, filtro, overlay ou waveform. Este plano adiciona a camada de "identidade de editor" (estilo CapCut). A regra de ouro do projeto — `exportCurrentTimeline` produz exatamente o que o preview mostra — passa a valer também para efeitos e overlays, então cada efeito precisa viver no mesmo pipeline usado por preview **e** export.

**Pré-requisito:** Onda 1 concluída (`docs/plan/onda-1-quick-wins.md`) — os snapshots de undo/redo já terão sido estendidos uma vez e o padrão de novos comandos estará consolidado.

## Design de Origem

- **Decisão aprovada:** Efeitos de cor e LUT como atributos do clipe aplicados no pipeline nativo compartilhado preview/export (Core Image no iOS, `media3-effect` no Android); fundo desfocado como modo de background na `TimelineCompositionConfig`; overlays (texto e sticker) como **bitmaps posicionados com intervalo de tempo** — o texto é rasterizado em PNG no lado Dart, e o nativo só composita bitmaps; waveform como utilitário standalone com cache, espelhando o padrão do `generateThumbnails`.
- **Alternativas descartadas:** Renderização de texto nativa (`AVVideoCompositionCoreAnimationTool` no iOS + `TextOverlay` no Android) — descartada porque o CoreAnimationTool só funciona no export (preview divergiria) e porque fontes renderizam diferente por plataforma, quebrando a paridade pixel a pixel; rasterizar no Dart garante texto idêntico no preview, no export e nas duas plataformas. Efeitos de cor via shader GLSL próprio no iOS — descartado; Core Image já cobre e é o padrão do compositor existente.
- **Tipo de mudança:** Logic

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models/clip_color_adjustments.dart` | criar | `ClipColorAdjustments` (brightness, contrast, saturation, temperature — todos em [-1.0, 1.0], default 0) + serialização |
| `lib/src/models/timeline_overlay.dart` | criar | `TimelineOverlay` (id, imagePath, posição normalizada, scale, opacity, rotação, `start`/`end` na timeline) + serialização |
| `lib/src/models/timeline_clip.dart` | editar | Novos campos: `colorAdjustments` (`ClipColorAdjustments?`), `lutPath` (`String?`) |
| `lib/src/models/timeline_composition_config.dart` | editar | Novo campo `backgroundMode` (enum `TimelineBackground { black, blur }`) + `backgroundBlurSigma` |
| `lib/src/overlay/text_overlay_rasterizer.dart` | criar | Rasteriza `TextOverlaySpec` (texto, fonte, tamanho, cor, fundo, padding) em PNG via `dart:ui` e devolve o path do arquivo |
| `lib/video_ultra_player_platform_interface.dart` | editar | Novos métodos: `setClipColorAdjustments`, `setClipLut`, `setOverlays`, `getWaveform` |
| `lib/video_ultra_player_method_channel.dart` | editar | Implementação via `MethodChannel` dos quatro métodos |
| `lib/src/native_timeline_player.dart` | editar | API pública: efeitos por clipe, `setOverlays(List<TimelineOverlay>)` (substitui o conjunto — idempotente), `addTextOverlay` (açúcar: rasteriza + `setOverlays`), `getWaveform` |
| `lib/video_ultra_player.dart` | editar | Exportar novos modelos e enums |
| `ios/Classes/TimelineComposition.swift` | editar | Cadeia Core Image por clipe (cor → LUT), fundo blur, composição de overlays por frame — mesmo pipeline para preview e export |
| `ios/Classes/LutLoader.swift` | criar | Parse de arquivos `.cube` → dados para `CIColorCube` (com cache por path) |
| `ios/Classes/WaveformExtractor.swift` | criar | PCM via `AVAssetReader` → N amplitudes RMS normalizadas, com cache em disco |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | Roteamento dos quatro comandos novos |
| `ios/Classes/TimelineEditModel.swift` | editar | Snapshots incluem colorAdjustments/lutPath/overlays |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineCompositionController.kt` | editar | `Effects` por clipe (`Brightness`, `Contrast`, `HslAdjustment`, `RgbAdjustment` p/ temperatura, `SingleColorLut`), fundo blur, `BitmapOverlay` com janela de tempo |
| `android/src/main/kotlin/com/andre/video_ultra_player/LutLoader.kt` | criar | Parse de `.cube` → bitmap/array para `SingleColorLut` (com cache) |
| `android/src/main/kotlin/com/andre/video_ultra_player/WaveformExtractor.kt` | criar | `MediaExtractor` + `MediaCodec` → amplitudes RMS normalizadas, com cache |
| `android/src/main/kotlin/com/andre/video_ultra_player/VideoUltraPlayerPlugin.kt` | editar | Roteamento dos quatro comandos novos |
| `android/src/main/kotlin/com/andre/video_ultra_player/TimelineEditModel.kt` | editar | Snapshots incluem os novos atributos |
| `test/clip_color_adjustments_test.dart` | criar | Serialização, defaults e validação de range |
| `test/timeline_overlay_test.dart` | criar | Serialização, validação de `start < end` e opacity/scale |
| `test/text_overlay_rasterizer_test.dart` | criar | Rasterização gera PNG válido com dimensões > 0 |
| `test/native_timeline_player_test.dart` | editar | Novas APIs delegam à platform com validações |
| `test/video_ultra_player_method_channel_test.dart` | editar | Novos method calls (nome + argumentos) |
| `example/lib/editor/editor_controller.dart` | editar | Ações de cor, LUT, fundo, texto, sticker e waveform |
| `example/lib/editor/editor_screen.dart` | editar | Painel de ajustes de cor, galeria de LUTs, editor de texto, waveform na régua da trilha de áudio |

## Fases

### Fase 1 — Testes dos modelos Dart (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Criar `test/clip_color_adjustments_test.dart`: defaults zerados, `toJson`/`copyWith`, valores fora de [-1, 1] lançam `ArgumentError`
- [ ] Criar `test/timeline_overlay_test.dart`: serialização completa, `start >= end` lança `ArgumentError`, opacity fora de [0, 1] lança `ArgumentError`
- [ ] Em `test/timeline_clip_test.dart`: `colorAdjustments` e `lutPath` em `toJson`/`copyWith` (incluindo remoção via copyWith explícito)
- [ ] Em `test/timeline_composition_config_test.dart`: `backgroundMode`/`backgroundBlurSigma` com defaults (`black`, sigma 20)
- [ ] Verificação: novos testes compilam e falham pelos motivos certos

### Fase 2 — Implementação dos modelos Dart

- [ ] Criar `lib/src/models/clip_color_adjustments.dart` e `lib/src/models/timeline_overlay.dart`
- [ ] Adicionar `colorAdjustments`/`lutPath` em `lib/src/models/timeline_clip.dart` e `backgroundMode`/`backgroundBlurSigma` em `lib/src/models/timeline_composition_config.dart`
- [ ] Exportar os novos tipos em `lib/video_ultra_player.dart`
- [ ] Verificação: testes da Fase 1 passam; `flutter analyze` limpo

### Fase 3 — Testes e implementação do contrato platform/channel

> Testes primeiro; implementação na sequência dentro da mesma fase.

- [ ] Em `test/video_ultra_player_method_channel_test.dart`: cobrir `setClipColorAdjustments`, `setClipLut`, `setOverlays`, `getWaveform` (nome do método + payload)
- [ ] Em `test/native_timeline_player_test.dart`: `setOverlays` aceita lista vazia (limpa overlays); `getWaveform` funciona sem `load` (utilitário standalone); `setClipLut(null)` remove o LUT
- [ ] Implementar os quatro métodos em `lib/video_ultra_player_platform_interface.dart` e `lib/video_ultra_player_method_channel.dart`
- [ ] Implementar a API pública em `lib/src/native_timeline_player.dart`
- [ ] Verificação: todos os testes passam; `flutter analyze` limpo

### Fase 4 — Rasterizador de texto no Dart

- [ ] Criar `test/text_overlay_rasterizer_test.dart`: rasterizar um `TextOverlaySpec` produz arquivo PNG existente com largura/altura > 0; texto vazio lança `ArgumentError`
- [ ] Criar `lib/src/overlay/text_overlay_rasterizer.dart`: `ParagraphBuilder`/`Canvas` de `dart:ui` → `Image.toByteData(png)` → arquivo em cache dir, escala 2x para nitidez
- [ ] Adicionar açúcar `addTextOverlay(TextOverlaySpec spec, {start, end, position...})` em `NativeTimelinePlayer` que rasteriza e delega para `setOverlays`
- [ ] Verificação: `flutter test` passa; `flutter analyze` limpo

### Fase 5 — iOS: ajustes de cor, LUT e fundo desfocado

- [ ] `ios/Classes/LutLoader.swift`: parser de `.cube` (tamanho, domínio, tabela RGB) → `Data` RGBA float para `CIColorCube`, com cache em memória por path
- [ ] `TimelineComposition.swift`: cadeia CI por clipe — `CIColorControls` (brightness/contrast/saturation) → `CITemperatureAndTint` (temperature) → `CIColorCube` (quando `lutPath` presente) — aplicada no mesmo ponto do pipeline usado por preview e export
- [ ] `TimelineComposition.swift`: quando `backgroundMode == blur`, compor camada de fundo com o próprio frame em aspect-fill + `CIGaussianBlur` (sigma da config) atrás do frame em aspect-fit
- [ ] `TimelineEditModel.swift`: snapshots incluem colorAdjustments/lutPath
- [ ] `VideoUltraPlayerPlugin.swift`: rotear `setClipColorAdjustments` e `setClipLut`
- [ ] Verificação: build Swift do exemplo compila

### Fase 6 — iOS: overlays e waveform

- [ ] `TimelineComposition.swift`: manter lista de overlays ativa; por frame, compor os bitmaps (via `CIImage` com transform de posição/scale/rotação e alpha) cujo intervalo `start–end` contém o timestamp — preview e export pelo mesmo caminho
- [ ] `VideoUltraPlayerPlugin.swift`: rotear `setOverlays` (substitui conjunto; lista vazia limpa) e incluir overlays nos snapshots do `TimelineEditModel.swift`
- [ ] Criar `ios/Classes/WaveformExtractor.swift`: `AVAssetReader` lê PCM linear, calcula RMS em N janelas, normaliza [0, 1], cacheia JSON em disco por `(path, samples, range)`
- [ ] `VideoUltraPlayerPlugin.swift`: rotear `getWaveform`
- [ ] Verificação: build Swift do exemplo compila

### Fase 7 — Android: ajustes de cor, LUT e fundo desfocado

- [ ] `android/.../LutLoader.kt`: parser de `.cube` → `SingleColorLut` (via array/bitmap N×N²), com cache em memória por path
- [ ] `TimelineCompositionController.kt`: montar `Effects` por clipe — `Brightness`, `Contrast`, `HslAdjustment` (saturação), `RgbAdjustment` (temperatura: ganho R/B) e `SingleColorLut` — usados tanto no `CompositionPlayer` quanto no `Transformer` (mesma `Composition`)
- [ ] `TimelineCompositionController.kt`: fundo desfocado — camada de fundo aspect-fill com blur gaussiano (efeito de blur do `media3-effect`; se indisponível na 1.10.1, shader GLSL próprio via `GlShaderProgram`) atrás do frame em aspect-fit
- [ ] `TimelineEditModel.kt`: snapshots incluem os novos atributos
- [ ] `VideoUltraPlayerPlugin.kt`: rotear `setClipColorAdjustments` e `setClipLut`
- [ ] Verificação: `flutter build apk --debug` do exemplo compila

### Fase 8 — Android: overlays e waveform

- [ ] `TimelineCompositionController.kt`: overlays via `OverlayEffect` + `BitmapOverlay` com `OverlaySettings` (posição/scale/alpha/rotação) e janela de tempo (overlay consulta o timestamp do frame para decidir visibilidade)
- [ ] `VideoUltraPlayerPlugin.kt`: rotear `setOverlays`; snapshots no `TimelineEditModel.kt`
- [ ] Criar `android/.../WaveformExtractor.kt`: `MediaExtractor` + `MediaCodec` decodifica para PCM, RMS em N janelas, normaliza, cache em disco por `(path, samples, range)`
- [ ] `VideoUltraPlayerPlugin.kt`: rotear `getWaveform`
- [ ] Verificação: `flutter build apk --debug` do exemplo compila

### Fase 9 — App de exemplo e documentação

- [ ] `example/lib/editor/editor_controller.dart`: ações de ajuste de cor, seleção de LUT (assets `.cube` de demo), toggle de fundo desfocado, adicionar texto/sticker, carregar waveform da trilha de áudio
- [ ] `example/lib/editor/editor_screen.dart`: painel de sliders de cor, galeria de LUTs, botão "Texto" com editor simples, render da waveform na régua de áudio
- [ ] Adicionar 2–3 arquivos `.cube` de demonstração em `example/assets/`
- [ ] Atualizar `CHANGELOG.md` e a versão em `pubspec.yaml`
- [ ] Verificação: `flutter analyze` limpo no pacote e no `example`; `flutter test` completo passa

### Fase 10 — Atualizar Flows

- [ ] `docs/flow/native-timeline-player.md`: documentar efeitos por clipe, background mode, overlays (incluindo a decisão de rasterizar texto no Dart) e `getWaveform`
- [ ] `docs/flow/ios-native-layer.md`: cadeia Core Image, `LutLoader`, `WaveformExtractor` e composição de overlays
- [ ] `docs/flow/android-implementation.md`: `Effects` do media3-effect, `LutLoader`, `BitmapOverlay` com janela de tempo e `WaveformExtractor`
- [ ] `docs/flow/project-structure.md`: novos arquivos nas árvores iOS/Android/lib
- [ ] Verificação: resumos (`> **Resumo:**`) dos flows continuam fiéis ao conteúdo

## Critérios de Sucesso

- [ ] Ajustes de cor, LUT, fundo desfocado e overlays aparecem no preview **e** no MP4 exportado de forma idêntica, nas duas plataformas
- [ ] Texto rasterizado no Dart renderiza igual no iOS e no Android (mesmo PNG)
- [ ] `getWaveform` retorna N amplitudes normalizadas e a segunda chamada idêntica vem do cache
- [ ] Undo/redo preserva efeitos e overlays
- [ ] Build sem erros (analyze + APK debug + build iOS do exemplo)
- [ ] Todos os testes unitários passando
- [ ] _(manual — feito pelo usuário)_ Validação funcional no app de exemplo (aplicar filtro, texto sobre o vídeo, exportar e comparar com o preview)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `media3-effect` 1.10.1 não expor blur gaussiano público/estável | Alta | Implementar shader GLSL próprio via `GlShaderProgram` (blur separável em 2 passes); a interface pública do plugin não muda |
| LUT produzir cores levemente diferentes entre `CIColorCube` e `SingleColorLut` (interpolação/espaço de cor) | Média | Usar o mesmo tamanho de cube e interpolação trilinear; validar com LUT identidade (resultado deve ser bit-a-bit igual ao original) |
| Custo de Core Image por frame (cor + LUT + blur + overlays) derrubar FPS do preview em devices antigos | Média | Reutilizar `CIContext` único, encadear filtros em uma única renderização e desligar blur de fundo abaixo de um threshold de performance |
| Overlay com janela de tempo no Android: `BitmapOverlay` não recebe timestamp diretamente na versão atual | Média | Usar a variante de overlay que expõe `presentationTimeUs` (ou custom `TextureOverlay`); validar API na 1.10.1 antes da Fase 8 |
| Rasterização de texto no Dart sem acesso às fontes do app consumidor | Baixa | `TextOverlaySpec` aceita `fontFamily` já carregada no engine Flutter do app; documentar que fontes customizadas devem estar registradas no app |

## Rollback

Reverter o(s) commit(s) da onda. Mudanças são aditivas ao contrato; nenhum consumidor existente quebra. Arquivos novos (`LutLoader`, `WaveformExtractor`, rasterizador) podem ser removidos sem afetar o restante.

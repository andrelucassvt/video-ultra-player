# Native Timeline Player — Overview

> **Objetivo:** Substituir `video_player` por um pacote Flutter plugin próprio que usa composição nativa (`AVMutableComposition` no iOS / Media3 `CompositionPlayer` no Android) para entregar playback verdadeiramente gapless de uma timeline com múltiplos clipes — CapCut-like.

> ⚠️ **Contexto deste repositório.** Este pacote (`video_ultra_player`, `com.andre.video_ultra_player`) está hoje como skeleton de plugin (`flutter create --template=plugin`): Dart/iOS/Android ainda são o boilerplate `getPlatformVersion`. Os arquivos do app citados adiante — `SequencePreviewPlayer`, `VideoEditorService`, `TimelinePlaybackModel`, `plan/fluid-video-preview.md` — **vivem no app consumidor, não neste pacote**, e não podem ser validados aqui. O channel deve usar o nome do pacote (`video_ultra_player`), não `com.luma_vid/...` (resíduo de outro contexto).

## O problema central com `video_player`

O `video_player` usa `AVPlayer` (iOS) / ExoPlayer (Android) **por clipe** — cada `VideoPlayerController` é um player separado. Mesmo com pré-carga, o swap de duas texturas causa flash ou gap perceptível porque são dois pipelines de renderização distintos.

CapCut usa **uma composição única** onde todos os clipes são segmentos de uma mesma timeline renderizada por um único decoder + uma única textura GPU.

---

## API Dart (surface pública)

```dart
class NativeTimelinePlayer {
  // Carrega a timeline completa de uma vez
  Future<void> load(List<TimelineClip> clips);

  // Controles básicos
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration globalPosition);
  Future<void> dispose();
  Future<void> setVolume(double volume); // 0.0–1.0

  // Atualiza crop/pan de um clipe sem recriar a composição
  Future<void> setClipAlignment(int index, double x, double y);

  // Estado
  Stream<TimelinePlayerState> get stateStream;
  // Emite: { globalPosition, clipIndex, localPosition, isPlaying, totalDuration }

  // Widget de renderização
  int get textureId; // usado em Texture(textureId: id)
}

class TimelineClip {
  final String path;          // file path absoluto (vídeo ou imagem)
  final MediaType type;       // video | image
  final Duration? duration;   // null = detectar; imagem = duração fixa (ex.: 3s)
  final Alignment alignment;  // pan/crop inicial
  final double scale;
}

enum MediaType { video, image }
```

---

## Camada Nativa — iOS

**Tecnologia:** `AVMutableComposition` + `AVPlayer`

Um único `AVPlayer` para toda a timeline:

```
AVMutableComposition
  ├── AVMutableCompositionTrack (video)
  │     ├── Segmento 0: clip A (0s → 5s)
  │     ├── Segmento 1: clip B (5s → 12s)
  │     └── Segmento 2: clip C (12s → 18s)
  └── AVMutableCompositionTrack (audio)
        └── (mesmos segmentos, com áudio quando presente)
```

### Detalhes de implementação

- **`AVVideoComposition`** com `AVMutableVideoCompositionInstruction` por segmento para aplicar `preferredTransform` (rotation) e `AVMutableVideoCompositionLayerInstruction` (scale/crop/alignment por clipe)
- **Imagens:** uma track de composição precisa de mídia real no time range, então **NÃO** use `AVVideoCompositionCoreAnimationTool` (é orientado a export). Opções viáveis: (a) **`AVVideoCompositing` custom** que emite o `CVPixelBuffer` da imagem durante o intervalo do clipe; ou (b) pré-gerar um vídeo curto a partir da imagem e inserir como segmento normal.
- **Renderização:** ❗ `AVPlayerLayer` **não é capturável** (seu `contents` não é legível). Use **`AVPlayerItemVideoOutput.copyPixelBuffer(forItemTime:)`** acionado por `CADisplayLink`, alimentando o protocolo `FlutterTexture.copyPixelBuffer` — mesmo mecanismo do `video_player` oficial.
- **Seek frame-accurate:** `seekTo(_:toleranceBefore:toleranceAfter:)` com tolerância **zero** para o seek final; durante **scrub** use tolerância não-zero (zero é caro e trava o arrasto).

### Eventos para Flutter

- `periodicTimeObserver` a cada ~33ms → emite posição global
- `clipIndex` calculado no lado nativo cruzando a posição com a tabela de segmentos da composição
- `AVPlayerItem.didPlayToEndTime` → notifica fim/loop

---

## Camada Nativa — Android

**Tecnologia:** Media3 **`CompositionPlayer`** (`androidx.media3.transformer`)

> **Por que NÃO um playlist do ExoPlayer.** `ExoPlayer.setMediaItems([...])` reproduz uma playlist com transição gapless **de áudio**, mas continua sendo N media sources com N configurações de decoder. Entre vídeos heterogêneos (resoluções/codecs diferentes) há reset de renderer no boundary → possível stutter. Isso **não** é o paralelo do `AVMutableComposition`.
>
> O paralelo real é **`CompositionPlayer`**: um player de preview em tempo real de uma `Composition` / `EditedMediaItemSequence`, com efeitos por item — a contraparte Android do single-composition do iOS.

```
CompositionPlayer
  └── Composition
        └── EditedMediaItemSequence
              ├── EditedMediaItem  (clip A — vídeo)
              ├── EditedMediaItem  (clip B — vídeo)
              └── EditedMediaItem  (imagem — MediaItem com setImageDurationMs)
```

> ⚠️ **Risco de maturidade.** `CompositionPlayer` é uma API relativamente nova/experimental; versões iniciais tiveram limitações (sequências, formatos suportados, surface). **Validar na versão exata do Media3 a ser fixada** (spike curto) antes de comprometer; fallback documentado = ExoPlayer playlist com caveat de transição.

### Detalhes de implementação

- **Troca de clipe / `clipIndex`:** derivar da posição global cruzando com a tabela de durações da sequência (mesma matemática do `TimelinePlaybackModel`). `Player.Listener.onMediaItemTransition` se aplica ao caminho de playlist do ExoPlayer; com `CompositionPlayer` o boundary é interno à composição.
- **Renderização:** ❗ **não se captura um `SurfaceView`.** Pegue um `SurfaceTexture` do `TextureRegistry` do Flutter → embrulhe num `Surface` → entregue ao player (`setVideoSurface` / surface da `CompositionPlayer`). Isso é o que de fato vira `Texture(textureId:)`.
- **Seek:** por posição global em ms na composição; durante scrub, aceitar seek aproximado.
- **Alignment/crop por clipe:** via `Effects`/`VideoEffects` por `EditedMediaItem`, ou aplicar o transform no widget `Texture` do lado Flutter (mais simples para pan/crop ao vivo).

### Imagens no Android

- Imagens entram como `EditedMediaItem` cujo `MediaItem` usa **`MediaItem.Builder().setImageDurationMs(...)`** (suporte de imagem do Media3 via `ImageRenderer`). **Não existem** `ImageMediaItem` nem gate "API 34+" — o suporte depende da **versão do Media3**, não do SDK do Android.
- Fallback, se a versão fixada não suportar imagem na composição: pré-gerar um vídeo curto a partir da imagem e inserir como `EditedMediaItem` de vídeo normal.

---

## Flutter Channel Architecture

> Nomes alinhados ao pacote (`video_ultra_player`), não ao resíduo `com.luma_vid/...`.

```
MethodChannel: 'video_ultra_player/timeline_player'
  → load(clips: json)
  → play()
  → pause()
  → seekTo(positionMs: int)
  → setVolume(volume: double)
  → setClipAlignment(index: int, x: double, y: double)
  → dispose()

EventChannel: 'video_ultra_player/timeline_player/events'
  ← {
       globalPositionMs: int,
       clipIndex: int,
       localPositionMs: int,
       totalDurationMs: int,
       isPlaying: bool
     }

Texture ID → Widget Texture(textureId: id)
```

---

## Transições

CapCut renderiza transições **dentro da composição nativa** (sem FFmpeg no preview):

| Plataforma | Técnica |
|---|---|
| iOS | `AVVideoCompositionInstruction` com dois `layerInstruction` + filtro CoreImage no período de crossfade |
| Android | ExoPlayer custom Renderer + shader OpenGL durante a janela de transição |

**Decisão pragmática (recomendada para v1):** manter `VideoEditorService.buildTransitionPreview` via FFmpeg e exibir no overlay Flutter com `_TransitionPreviewStack` — já está implementado e funciona. Transições nativas ficam para fase futura.

---

## O que muda no `SequencePreviewPlayer`

O widget atual (`sequence_preview_player.dart`) vira um thin wrapper:

| Remove | Mantém |
|--------|--------|
| Pool de `VideoPlayerController` (current + next) | GestureDetector de pan → `setClipAlignment` |
| `_syncCurrentController` / `_preloadNext` / `_promoteNextController` | `_TransitionPreviewStack` com overlay FFmpeg |
| Timers de imagem (tratado nativamente) | `_PreviewSequenceIndicator` |
| Generation counters de async stale | `onPlaybackPositionChanged` / `onClipChanged` via `stateStream` |

```dart
// Antes: VideoPlayer(controller)
// Depois:
Texture(textureId: _player.textureId)
```

---

## O que o pacote NÃO toca

| Responsabilidade | Onde fica |
|---|---|
| Indicador de sequência (`1/3` + segmentos) | Flutter widget |
| Background blur | Flutter widget |
| UI de scrub (barra de timeline) | Flutter widget |
| Export / merge de vídeos | FFmpeg — não muda nada |
| `TimelinePlaybackModel` (math pura de posição) | Dart puro — continua igual |

---

## Entregáveis do pacote

1. **Uma textura GPU única** para toda a timeline (sem swap de texture)
2. **Composição nativa real** (`AVMutableComposition` / `ConcatenatingMediaSource`)
3. **Seek frame-accurate** por posição global em ms
4. **Stream de estado** com posição global + `clipIndex` atual
5. **Suporte a imagens** como clipes com duração configurável
6. **`setClipAlignment(index, x, y)`** para atualizar crop/pan sem recriar a composição
7. **Gapless verdadeiro** — zero gap no boundary por ser um único decodificador

---

## Esforço estimado por plataforma

| Área | Complexidade | Motivo |
|------|-------------|--------|
| iOS — composição de vídeos | Alta | `AVMutableComposition` + instrução de layer por clipe |
| iOS — render para textura | Média | `AVPlayerItemVideoOutput` + `CADisplayLink` → `FlutterTexture` |
| iOS — imagens na composição | Alta | `AVVideoCompositing` custom (CVPixelBuffer) ou pré-gerar vídeo curto |
| iOS — alignment/crop por clipe | Média | `setTransform(_:at:)` (estático) + swap de `videoComposition`, ou transform no widget `Texture` |
| Android — composição (CompositionPlayer) | **Alta / Risco** | API nova; validar maturidade na versão fixada (spike) |
| Android — render para textura | Média | `SurfaceTexture` do `TextureRegistry` → `Surface` → player |
| Android — imagens na composição | Média | `MediaItem.setImageDurationMs` (depende da versão do Media3); fallback = pré-encode |
| Flutter channel + EventChannel | Baixa | Padrão de plugin Flutter |
| Integração no `SequencePreviewPlayer` | Baixa | Troca `VideoPlayer` por `Texture` + escuta `stateStream` |

---

## Relação com o plano atual

Este pacote substitui a **Fase Futura** descrita em `plan/fluid-video-preview.md` (composição nativa via platform channels). As Fases 1–3 do plano atual (`TimelinePlaybackModel`, durações no cubit) permanecem válidas e complementares — o modelo de posição Dart ainda é útil para scrub e indicador de sequência mesmo com o player nativo.

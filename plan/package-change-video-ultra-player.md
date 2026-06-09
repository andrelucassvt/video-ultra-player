# Mudança de pacote: `video_ultra_player` — seek por clipe

> **Status:** Opcional / recomendada. O plano `seek-preview-on-clip-tap.md` funciona **sem** esta mudança (workaround no lado Dart). Esta mudança torna a solução mais simples, precisa e barata.

## Problema

Para mover o preview ao início de um clipe específico, o app precisa do offset global daquele clipe (soma das durações dos clipes anteriores). Hoje o plugin `video_ultra_player` (v1.0.1) expõe apenas:

- `seekTo(Duration position)` — seek por posição global, **sem** variante por índice de clipe.
- `TimelinePlayerState` com `globalPosition`, `clipIndex`, `localPosition`, `totalDuration` — não retorna as **fronteiras/durações de cada clipe**.
- `TimelineClip.duration` é `null` para vídeos (o nativo usa a duração natural), então o app **não conhece** a duração dos clipes de vídeo.

Consequência no app: para computar offsets, é preciso **probar** a duração de cada vídeo via `VideoPlayerController.file().initialize()` no lado Dart — inicialização redundante (o nativo já tem essa informação na composição), com risco de imprecisão e custo por clipe.

## Mudança proposta no pacote

Implementar **uma** das duas opções (preferência pela A):

### Opção A — `seekToClip(int clipIndex)` (preferida)

Novo método que faz o seek diretamente ao início (local position 0) do clipe de índice `clipIndex`, resolvido no lado nativo onde as fronteiras já são conhecidas.

**Assinaturas a adicionar:**

- `video_ultra_player_platform_interface.dart`:
  ```dart
  Future<void> seekToClip(int textureId, int clipIndex) {
    throw UnimplementedError('seekToClip() has not been implemented.');
  }
  ```
- `video_ultra_player_method_channel.dart`:
  ```dart
  @override
  Future<void> seekToClip(int textureId, int clipIndex) {
    return methodChannel.invokeMethod<void>('seekToClip', <String, Object?>{
      'textureId': textureId,
      'clipIndex': clipIndex,
    });
  }
  ```
- `src/native_timeline_player.dart`:
  ```dart
  Future<void> seekToClip(int clipIndex) {
    return _platform.seekToClip(_requireTextureId(), clipIndex);
  }
  ```
- **iOS (AVFoundation)** e **Android (Media3):** handler `seekToClip` que resolve o `CMTime`/posição da fronteira do clipe `clipIndex` na composição e faz o seek.

### Opção B — expor durações/fronteiras dos clipes

Adicionar ao `TimelinePlayerState` (ou a um novo método `getClipBoundaries()`) a lista de durações resolvidas por clipe, ex.: `List<Duration> clipDurations` ou `List<Duration> clipStartOffsets`. O app computa o offset e usa o `seekTo` existente.

Menos preferida: mantém a lógica de soma no app e exige cuidado com sincronização (durações de imagem mutáveis vs. vídeo).

## Impacto no app se a mudança for adotada

Adotando a Opção A, o plano `seek-preview-on-clip-tap.md` simplifica drasticamente:

- **Remover** o probing de duração de vídeo, o `_videoDurationCache` e a tabela `_clipStartOffsets` do `VideoEditCubit`.
- **Remover** o método `seekToClip(int)` do app (cálculo de offset) e substituí-lo por uma chamada direta `_timelineService.seekToClip(index)`.
- Adicionar `seekToClip(int clipIndex)` à interface `VideoTimelineService` e à impl `VideoTimelineServiceImpl` (encapsulando `NativeTimelinePlayer.seekToClip`).
- Testes ficam triviais: verificar que `onClipTap(i)` chama `_timelineService.seekToClip(i)`.

## Decisão pendente (para o usuário)

- **Seguir o plano atual** (workaround Dart, sem tocar no pacote) — entrega imediata, sem dependência de release do plugin.
- **Implementar a mudança no pacote primeiro** (Opção A) — exige acesso/release do `video_ultra_player` (atualmente `pub.dev` v1.0.1); o app passaria a depender da nova versão.

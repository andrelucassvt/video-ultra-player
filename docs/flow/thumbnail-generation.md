---
generated_at: 2026-07-31
source_commit: 1e11b62
source_state: clean
verified_at: 2026-07-31
status: current
related_plans: []
---

# Flow: Geração de Thumbnails

> **Resumo:** Utilitário standalone que extrai frames de um vídeo em timestamps específicos, salva JPEGs em cache de disco e devolve os paths — sem depender de nenhum player carregado.

## Visão Geral

`NativeTimelinePlayer.generateThumbnails(videoPath, timestamps, width:)` é o único método da API pública que **não** exige `load`: não passa por `_requireTextureId()` e não toca no mapa de controllers nativos. Ele converte a lista de `Duration` em milissegundos e chama o channel com `{videoPath, timestampsMs, width}`; o retorno é uma lista de paths absolutos de arquivos JPEG, na mesma ordem dos timestamps pedidos (com omissões quando a extração falha).

O cache é o ponto central do design: nas duas plataformas a chave é `{hash(videoPath)}_{timestampMs}_{width}.jpg`, com um hash djb2 do path em hexadecimal — isso evita nomes longos e path traversal. Se o arquivo já existe, ele é devolvido sem re-extração. O diretório é `NSTemporaryDirectory()/vup_thumbs/` no iOS e `context.cacheDir/vup_thumbs/` no Android. Nenhuma das implementações limpa esse diretório — é cache do sistema, sujeito à limpeza do OS.

No iOS a extração usa `AVAssetImageGenerator` com `appliesPreferredTrackTransform = true` (respeita a rotação da fonte) e tolerância **zero** nas duas direções, o que dá precisão de frame ao custo de latência — há um comentário no código sugerindo `CMTimeMake(1, 10)` quando velocidade importa mais. Tudo roda numa fila global `.userInitiated`; o `completion` é chamado nessa mesma thread e o plugin faz o `DispatchQueue.main.async` antes de responder ao Flutter.

No Android usa-se `MediaMetadataRetriever` com um único `setDataSource` para toda a lista (o retriever é reaproveitado e liberado no `finally`). A partir da API 27 (`O_MR1`) usa `getScaledFrameAtTime`, calculando a altura proporcional a partir dos metadados de largura/altura; abaixo disso pega o frame cheio e reduz com `Bitmap.createScaledBitmap`. Em ambos os caminhos o modo é `OPTION_CLOSEST_SYNC` — ou seja, o frame devolvido é o keyframe mais próximo, não necessariamente o timestamp exato. O trabalho roda no `thumbnailExecutor` (cached thread pool) do plugin e o resultado volta pelo `mainHandler`.

No app de exemplo, cada tile de clipe pede de 1 a 5 thumbnails (uma por segundo, com teto de 5) posicionadas nos centros de intervalos iguais, e o `EditorController` deduplica requisições em `_thumbnailRequests` por `(path, width, timestamps)`. Esse cache é limpo depois de qualquer edição, já que as durações resolvidas mudam.

## Passo a Passo

1. **Pedido na UI** — `example/lib/editor/widgets/clip_strip.dart` → `_ClipThumbnailRail`
   `FutureBuilder` sobre `controller.thumbnailPathsForClip(index, duration, width: 120)`; clipes de imagem usam `Image.file` direto, sem thumbnail.
2. **Cálculo dos timestamps** — `example/lib/editor/editor_controller.dart` → `_thumbnailTimestamps`
   `count = (durationMs / 1000).ceil().clamp(1, 5)`; cada timestamp é o centro do seu intervalo.
3. **Deduplicação** — `EditorController.thumbnailPathsForClip`
   Chave `'${clip.path}|$width|<timestamps>'` em `_thumbnailRequests.putIfAbsent`.
4. **API pública** — `lib/src/native_timeline_player.dart` → `generateThumbnails`
   Converte `List<Duration>` em `List<int>` (ms) e delega; sem exigir `load`.
5. **Serialização** — `lib/video_ultra_player_method_channel.dart` → `generateThumbnails`
   `invokeMethod<List<dynamic>>('generateThumbnails', {videoPath, timestampsMs, width})` e `cast<String>()`, com fallback para lista vazia.
6. **iOS — roteamento** — `ios/Classes/VideoUltraPlayerPlugin.swift` → `case "generateThumbnails"`
   Exige `videoPath: String`, `timestampsMs: [Int]` e `width: Int`; caso contrário `invalid_arguments`.
7. **iOS — extração** — `ios/Classes/ThumbnailGenerator.swift` → `ThumbnailGenerator.shared.generate(...)`
   Fila `.userInitiated`; para cada timestamp confere o cache, senão `copyCGImage(at:actualTime:)`, redimensiona com `UIGraphicsImageRenderer` e grava JPEG com qualidade 0.8.
8. **iOS — retorno** — `DispatchQueue.main.async { result(paths) }`
9. **Android — roteamento** — `.../VideoUltraPlayerPlugin.kt` → `generateThumbnails(call, result)`
   Exige `applicationContext` (`not_attached`) e `videoPath` (`invalid_arguments`); `width` default 120.
10. **Android — extração** — `.../ThumbnailGenerator.kt` → `generate` / `generateFrame`
    Um `setDataSource` para a lista inteira; `getScaledFrameAtTime` (API ≥ 27) ou `getFrameAtTime` + `createScaledBitmap`; JPEG com qualidade 80.
11. **Android — retorno** — `mainHandler.post { result.success(paths) }`
12. **Render** — `_ClipThumbnailRail` divide a largura do tile pelo número de paths e desenha um `Image.file` por thumbnail, com `errorBuilder` para o fallback de ícone.

### Caminhos alternativos

- **Cache hit:** o path existente é devolvido sem extração nova.
- **Argumentos inválidos:** `invalid_arguments` nas duas plataformas (no iOS a checagem de tipos é estrita: `timestampsMs` precisa ser `[Int]`).
- **Plugin sem contexto (Android):** `not_attached`.
- **Extração falha num timestamp:** o timestamp é omitido do resultado — `continue` no iOS, `mapNotNull` no Android. A lista devolvida pode ser menor que a pedida.
- **Falha ao gravar o JPEG:** iOS usa `try?` e não adiciona o path; Android captura `Throwable` e devolve `null`.
- **Resultado vazio:** `_ClipThumbnailRail` mostra `_ClipFallbackIcon`.
- **Arquivo removido depois de cacheado:** `Image.file` cai no `errorBuilder` (o cache guarda só o path).

## Arquivos Envolvidos

| Camada | Arquivo | Responsabilidade |
|--------|---------|------------------|
| API pública | `lib/src/native_timeline_player.dart` | `generateThumbnails` (sem `textureId`) |
| Contrato | `lib/video_ultra_player_platform_interface.dart` | Assinatura e documentação do cache |
| Serialização | `lib/video_ultra_player_method_channel.dart` | Payload e `cast<String>()` |
| Modelo | `lib/src/models/clip_thumbnail.dart` | `ClipThumbnail.fromMap` (`path` + `timeMs`) |
| Nativo iOS | `ios/Classes/ThumbnailGenerator.swift` | Singleton, `AVAssetImageGenerator`, cache, resize |
| Nativo iOS | `ios/Classes/VideoUltraPlayerPlugin.swift` | Validação de argumentos e volta para a main thread |
| Nativo Android | `.../ThumbnailGenerator.kt` | `MediaMetadataRetriever`, cache, escala por versão de API |
| Nativo Android | `.../VideoUltraPlayerPlugin.kt` | `thumbnailExecutor`, `mainHandler` |
| Consumidor | `example/lib/editor/editor_controller.dart` | Timestamps, deduplicação, invalidação após edição |
| Consumidor | `example/lib/editor/widgets/clip_strip.dart` | `FutureBuilder`, divisão da largura, fallback |
| Testes | `test/clip_thumbnail_test.dart` | `fromMap` |
| Testes | `test/native_timeline_player_test.dart`, `test/video_ultra_player_method_channel_test.dart` | Delegação e payload |

## Regras de Negócio Relevantes

- **Não exige `load`** — é utilitário standalone, documentado como tal na API e no contrato.
- **Cache por `(videoPath, timestampMs, width)`** — chave `{djb2hex(path)}_{ts}_{width}.jpg` nas duas plataformas; segunda chamada idêntica é servida do disco.
- **`width` default 120 px** — altura sempre proporcional; o default está no Dart e é reforçado no Android (`?: 120`).
- **Ordem preservada, tamanho não garantido** — os timestamps que falham são omitidos.
- **iOS é frame-exato; Android é keyframe** — tolerância zero no `AVAssetImageGenerator` versus `OPTION_CLOSEST_SYNC` no `MediaMetadataRetriever`. Para o mesmo timestamp as plataformas podem devolver frames diferentes.
- **Rotação respeitada no iOS** — `appliesPreferredTrackTransform = true`.
- **Nunca roda na main thread** — fila global no iOS, `thumbnailExecutor` no Android (documentado no Kotlin: "Must NOT be called on the main thread").
- **Qualidade do JPEG** — 0.8 no iOS, 80 no Android.
- **No exemplo, no máximo 5 thumbnails por clipe** — `_thumbnailTimestamps` com `clamp(1, 5)`.

## Dependências Externas

- **iOS:** `AVAssetImageGenerator`, `UIImage`, `UIGraphicsImageRenderer`, `FileManager`, `NSTemporaryDirectory`.
- **Android:** `MediaMetadataRetriever`, `Bitmap`/`BitmapFactory`, `File`/`FileOutputStream`, `Build.VERSION`.

## Observações

- O cache não tem invalidação nem limite de tamanho: nada apaga `vup_thumbs/`, e a chave usa o path (não mtime nem tamanho), então **substituir um arquivo mantendo o mesmo path devolve thumbnails obsoletas**.
- `ClipThumbnail` existe como modelo público e tem teste, mas nenhum caminho do channel o produz — o retorno é `List<String>`.
- O hash djb2 não é criptográfico; colisão de paths distintos é teoricamente possível e resultaria em thumbnail trocada.
- A tolerância zero do iOS torna a extração sensivelmente mais lenta; o próprio código documenta a alternativa (`CMTimeMake(1, 10)`).
- No Android, `resolveSourceDurationMs`/`resolveSourceSize` (do controller) e o `ThumbnailGenerator` abrem `MediaMetadataRetriever` separados para o mesmo arquivo — não há retriever compartilhado.

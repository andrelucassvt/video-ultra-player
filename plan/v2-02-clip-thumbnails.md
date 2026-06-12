# V2-02 — Thumbnails de Clipe (régua da timeline)

> **Objetivo:** Expor uma API federada para gerar thumbnails de um clipe em timestamps dados (extração nativa, cacheada), para a régua de clipes da timeline renderizar miniaturas sem travar a UI.

## Contexto

A régua de clipes do wireframe (#4/#5) mostra miniaturas do conteúdo de cada clipe. Não existe geração de frames hoje. Pré-requisito visual do `v2-06`. **Decisão (overview #3):** extração nativa (`AVAssetImageGenerator` iOS, `MediaMetadataRetriever` Android), cacheada em arquivos por `(path, timestampMs, width)`.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `lib/src/models/clip_thumbnail.dart` | criar | `ClipThumbnail { String path; Duration time; }` + `fromMap` |
| `lib/video_ultra_player_platform_interface.dart` | editar | `Future<List<String>> generateThumbnails(String videoPath, List<int> timestampsMs, {int width})` |
| `lib/video_ultra_player_method_channel.dart` | editar | Implementar `generateThumbnails` → `invokeMethod('generateThumbnails', {...})` retornando lista de paths |
| `lib/src/native_timeline_player.dart` | editar | Método público `generateThumbnails(String videoPath, List<Duration> timestamps, {int width = 120})` |
| `ios/Classes/ThumbnailGenerator.swift` | criar | `AVAssetImageGenerator` (com `requestedTimeToleranceBefore/After = .zero` p/ precisão), grava PNG/JPEG em cache temp, retorna paths |
| `ios/Classes/VideoUltraPlayerPlugin.swift` | editar | Dispatch de `generateThumbnails` (assíncrono, fora da main thread) |
| `android/.../ThumbnailGenerator.kt` | criar | `MediaMetadataRetriever.getFrameAtTime` / `getScaledFrameAtTime`, grava bitmaps em cacheDir, retorna paths |
| `android/.../VideoUltraPlayerPlugin.kt` | editar | Dispatch de `generateThumbnails` em coroutine/executor |
| `test/clip_thumbnail_test.dart` | criar | `fromMap` |
| `test/native_timeline_player_test.dart` | editar | `generateThumbnails` delega e mapeia paths |
| `test/video_ultra_player_method_channel_test.dart` | editar | Payload de `generateThumbnails` |

**Nota de fluidez:** geração é **assíncrona e cacheada**; nunca na main thread nativa. A UI usa placeholder e troca por `Image.file` quando o path chega. Cache por chave `(path, timestampMs, width)` evita re-extração ao redimensionar a régua.

## Fases

### Fase 1 — Testes (contrato)

- [x] `test/clip_thumbnail_test.dart`: `ClipThumbnail.fromMap` lê `path` e `timeMs`.
- [x] `test/native_timeline_player_test.dart`: `generateThumbnails(path, [d0, d1])` chama plataforma com `[0, ...]` ms e devolve paths.
- [x] `test/video_ultra_player_method_channel_test.dart`: payload `{'videoPath', 'timestampsMs', 'width'}`.
- [x] Verificação: testes falham por método ausente.

### Fase 2 — Contrato Dart

- [x] Criar `ClipThumbnail`; exportar em `lib/video_ultra_player.dart`.
- [x] Adicionar `generateThumbnails` ao platform interface + method channel + `NativeTimelinePlayer`.
- [x] Verificação: `flutter test`/`flutter analyze` verdes.

### Fase 3 — Nativo iOS

- [x] `ThumbnailGenerator.swift`: `AVAssetImageGenerator`, `appliesPreferredTrackTransform = true`, tolerância zero, escala para `width`, salva em `NSTemporaryDirectory()/vup_thumbs/`, cache por chave.
- [x] Plugin dispatch assíncrono; retorna lista de paths na ordem dos timestamps.
- [ ] Verificação: paths existem e abrem como imagem; segunda chamada usa cache.

### Fase 4 — Nativo Android

- [x] `ThumbnailGenerator.kt`: `MediaMetadataRetriever`, `getScaledFrameAtTime(usec, OPTION_CLOSEST, width, height)`, salva em `context.cacheDir/vup_thumbs/`, cache por chave.
- [x] Plugin dispatch em executor/coroutine; libera o retriever no fim.
- [ ] Verificação: paridade com iOS; sem ANR ao gerar muitos frames.

## Critérios de Sucesso

- [ ] `generateThumbnails` retorna paths de imagens reais nos timestamps pedidos.
- [ ] Segunda chamada idêntica é servida do cache.
- [ ] Geração não bloqueia a UI Flutter nem a main thread nativa.
- [x] `flutter test`/`flutter analyze` verdes.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Geração lenta para muitos frames | Média | Limitar nº de thumbs por clipe (ex: 1 a cada N px de largura); gerar sob demanda no viewport |
| Cache cresce sem limite | Baixa | Diretório temp/cache do app; limpar no `dispose` ou por LRU simples |
| Imagens (MediaType.image) não têm frames | Baixa | Para `image`, a régua usa o próprio arquivo; `generateThumbnails` só p/ vídeo |

## Rollback

Aditivo; remover a API e os geradores. A régua cai para placeholder/cor sólida sem thumbnails.

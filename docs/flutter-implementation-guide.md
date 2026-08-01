# Guia de Implementação — Lado Flutter (`video_ultra_player`)

Como construir um editor de vídeo em Flutter consumindo o plugin: setup, player, preview, playback, edição, undo/redo, áudio, thumbnails, export e a arquitetura de UI. Baseado no app de referência em `example/`.

## 1. Setup

```yaml
dependencies:
  video_ultra_player:
    path: ../ # ou versão do pub
```

Permissões (necessárias só para os pickers e para salvar na galeria):

- **iOS** (`ios/Runner/Info.plist`): `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`.
- **Android** (`AndroidManifest.xml`): `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO` (API 33+) ou `READ_EXTERNAL_STORAGE` (≤32).

Dependências úteis do app (não são do plugin): `image_picker` (vídeos da galeria), `file_picker` (áudio), `gal` (salvar export na galeria).

## 2. Conceitos centrais

- **`textureId` é a sessão** — `load()` devolve um `int`; você o usa só para desenhar o `Texture`. Todos os comandos seguintes são métodos do próprio `NativeTimelinePlayer` (ele carrega o id internamente).
- **Preview = export** — o MP4 exportado é exatamente o que o preview mostra, porque os dois nascem da mesma composição nativa.
- **Tudo em `Duration` no Dart** — o plugin converte para milissegundos no channel.
- **O nativo não devolve a lista de clipes** — devolve só durações (`state.clipDurations`). A UI precisa manter um **espelho local** dos clipes (seção 6).
- **`trimEnd` é ponto absoluto na fonte**, não duração, e tem precedência sobre `duration` para vídeo. Para imagem, trim é ignorado — use `duration`.

## 3. Ciclo de vida do player

```dart
final player = NativeTimelinePlayer();

// Paths precisam ser de ARQUIVO no disco. Assets não valem —
// copie para um diretório temporário antes (ver seção 4).
final textureId = await player.load(
  clips,
  config: TimelineCompositionConfig(
    aspectRatio: OutputAspectRatio.ratio9x16,
    baseWidth: 1080, // 1..4096
  ),
);

// ... usar ...

await player.dispose(); // libera textura e compositor nativo
```

Regras:

- `load` com lista vazia lança `ArgumentError`.
- Qualquer método antes do `load` lança `StateError`.
- Trocar de timeline = `dispose()` + `load()` novo (não reutilize player entre timelines).
- `dispose()` sem `load` é no-op seguro.

## 4. Preparando a mídia

```dart
// Galeria → paths prontos
final files = await ImagePicker().pickMultiVideo();
final clips = [
  for (final f in files) TimelineClip(path: f.path, type: MediaType.video),
];

// Asset → copiar para arquivo primeiro
Future<File> assetToFile(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final dir = Directory('${Directory.systemTemp.path}/meu_editor');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${assetPath.split('/').last}');
  return file.writeAsBytes(data.buffer.asUint8List(), flush: true);
}
```

Modelo do clipe:

```dart
TimelineClip(
  path: path,
  type: MediaType.video,      // ou MediaType.image
  duration: null,             // vídeo: opcional; imagem: obrigatório
  trimStart: null,            // offset na fonte
  trimEnd: null,              // ponto ABSOLUTO de fim na fonte
  speed: 1.0,                 // [0.5, 2.0]
  scale: 1.0,                 // > 0; zoom antes do crop
  alignment: Alignment.center,// âncora do pan/crop
)
```

## 5. Preview e playback

### Renderizar

```dart
if (player.textureId case final id?)
  AspectRatio(
    aspectRatio: 9 / 16,
    child: ColoredBox(
      color: Colors.black,
      child: Texture(textureId: id),
    ),
  )
```

### Ouvir o estado

```dart
StreamBuilder<TimelinePlayerState>(
  stream: player.stateStream,
  initialData: const TimelinePlayerState.initial(),
  builder: (context, snapshot) {
    // Erros de playback (Android) chegam como ERRO DO STREAM,
    // não como exceção de método:
    if (snapshot.hasError) { /* exibir na UI */ }
    final state = snapshot.data ?? const TimelinePlayerState.initial();
    // state.globalPosition / clipIndex / localPosition / isPlaying /
    // totalDuration / clipDurations / canUndo / canRedo
  },
)
```

### Controles

```dart
// A timeline NÃO faz loop: perto do fim, volte ao zero antes do play.
Future<void> playOrPause(TimelinePlayerState state) async {
  if (state.isPlaying) return player.pause();
  final atEnd = state.totalDuration - state.globalPosition <
      const Duration(milliseconds: 100);
  if (atEnd) await player.seekTo(Duration.zero);
  await player.play();
}

await player.seekTo(position);      // posição global na timeline
await player.seekToClip(clipIndex); // início de um clipe
await player.setVolume(0.8);        // [0.0, 1.0], fora disso = RangeError
```

### Scrub (arraste do playhead) com throttle

Seek nativo é assíncrono e caro — enfileire durante o arrasto e commite no release:

```dart
Timer? _seekTimer;
Duration? _pendingSeek;

void previewSeek(Duration position) {
  _pendingSeek = position;
  _seekTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
    final next = _pendingSeek;
    if (next != null) {
      _pendingSeek = null;
      player.seekTo(next); // fire-and-forget
    }
  });
}

Future<void> commitSeek(Duration position) async {
  _seekTimer?.cancel();
  _seekTimer = null;
  _pendingSeek = null;
  await player.seekTo(position);
}
```

Durante o arrasto, mostre a posição num `_dragPosition` local (o playhead se move já, sem esperar o stream) e limpe-o quando o seek confirmar.

## 6. Edição da timeline

Todos os métodos preservam `textureId` e posição de playback:

```dart
await player.trimClip(i, trimStart: a, trimEnd: b); // b absoluto na fonte
await player.splitClip(i, atLocalPosition);         // > zero; posição DENTRO do clipe
await player.insertClip(atIndex, clip);
await player.removeClip(i);      // o plugin permite remover o último — barre na UI
await player.moveClip(from, to); // índices iguais = no-op
await player.replaceClip(i, clip);
await player.setClipSpeed(i, 1.5);      // [0.5, 2.0]
await player.setClipAlignment(i, x, y); // x/y em [-1, 1]
```

### Regra de ouro: commit só no release do gesto

Cada comando **reconstrói a composição nativa**. Nunca chame a cada tick de arrasto:

```dart
// Slider de velocidade:
Slider(
  value: draftSpeed,
  onChanged: (v) => setState(() => draftSpeed = v),   // só UI
  onChangeEnd: (v) => controller.setSelectedClipSpeed(v), // nativo aqui
)
```

### Espelho local dos clipes

O nativo não devolve a lista editada — replique cada mutação localmente **após** o await:

```dart
List<TimelineClip> _clips;

Future<void> split(TimelinePlayerState state) async {
  final i = state.clipIndex;
  if (state.localPosition >= clipDuration(i)) return; // split no fim = no-op
  await player.splitClip(i, state.localPosition);
  // Replica a semântica nativa (posição local × speed vira offset na fonte):
  final clip = _clips[i];
  final splitAt = state.localPosition * clip.speed;
  final first = clip.copyWith(trimEnd: (clip.trimStart ?? Duration.zero) + splitAt);
  final second = clip.copyWith(trimStart: (clip.trimStart ?? Duration.zero) + splitAt);
  _clips.replaceRange(i, i + 1, [first, second]);
  notifyListeners();
}
```

Use `state.clipDurations` para as larguras da UI (já vêm com speed aplicado) e tenha um fallback calculado de trim/duration/speed até o primeiro report.

## 7. Undo/redo

O histórico vive no nativo (50 snapshots); a UI mantém pilhas próprias para o espelho local. Habilite os botões só quando **os dois lados concordam**:

```dart
final canUndo = state.canUndo && controller.canUndo;

Future<void> undo() async {
  final snapshot = _undoSnapshots.removeLast();
  _redoSnapshots.add(currentSnapshot());
  await player.undo();
  _clips = snapshot.clips; // restaura o espelho local
  notifyListeners();
}
```

Toda operação de edição da UI deve: empurrar snapshot local → chamar o nativo → atualizar o espelho → invalidar caches derivados (thumbnails).

## 8. Trilha de áudio

```dart
await player.setAudioTrack(AudioTrack(
  path: audioPath,
  offset: Duration.zero,
  volume: 1.0,          // [0.0, 1.0]
  trimStart: null,      // offset na fonte de áudio
  trimEnd: null,        // ponto absoluto de fim na fonte
  fadeIn: Duration(milliseconds: 500),
  fadeOut: Duration(milliseconds: 800),
));
await player.removeAudioTrack();
```

- Uma trilha por player; `setAudioTrack` substitui a anterior e entra no histórico de undo.
- A duração é capada pela timeline (áudio além do fim é cortado) e o áudio **não estende** a duração total.
- Volume: preview local no arrasto, `setAudioTrack` só no release (mesma regra do commit).

## 9. Thumbnails da timeline

```dart
// Utilitário standalone — não exige load. Cache nativo por (path, ts, width).
final paths = await player.generateThumbnails(
  videoPath,
  timestamps,      // List<Duration>, ex.: 1 a 5 por clipe
  width: 120,
);
// paths pode vir MENOR que timestamps (falhas são omitidas) — tenha fallback.
Image.file(File(paths[i]), fit: BoxFit.cover)
```

Dedupe requisições (`Map<String, Future<List<String>>>`) e **invalide o cache de requisições a cada edição** (trim/split/remove/move/speed/troca de timeline).

## 10. Export

```dart
// Do estado editado (preview = export). Requer load.
final outPath = await player.exportCurrentTimeline(outputPath: outputPath);

// Progresso: o stream só existe DURANTE o export.
// Estruture assim: inicie a escuta no mesmo frame em que dispara o export.
final progressStream = player.exportProgress; // StateError fora de export
```

```dart
// Alternativa sem player carregado (ignora trilha de áudio externa):
final outPath = await player.exportTimeline(clips, outputPath: path);
```

Padrão completo com galeria (como no exemplo):

```dart
final dir = Directory('${Directory.systemTemp.path}/exports');
await dir.create(recursive: true);
final path = '${dir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4';

final future = player.exportCurrentTimeline(outputPath: path);
// mostre o percentual com StreamBuilder em player.exportProgress
final exported = await future;

await Gal.requestAccess();
await Gal.putVideo(exported);
await File(exported).delete(); // o temporário é sua responsabilidade
```

- Um export por player por vez (`StateError` caso contrário).
- Falha de permissão da galeria → exiba como erro na UI.

## 11. Arquitetura de UI recomendada

A referência é o `example/` — simples de propósito:

- **Um `EditorController extends ChangeNotifier`** como único ponto de contato com o `NativeTimelinePlayer`. Concentra: `_clips` (espelho), `textureId`, clipe selecionado, config de saída, zoom (`pixelsPerSecond`, clamp 44–132), loading/exporting/error, cache de thumbnails, throttle de seek e pilhas de undo/redo locais.
- **Dois níveis de reatividade na tela**: `AnimatedBuilder` no controller (estado do app) com `StreamBuilder<TimelinePlayerState>` dentro (posição/playback do nativo).
- **Layout**: barra superior (origem/resolução) → preview (`Texture`) → toolbar (play, tempo, ações, undo/redo, zoom, export) → timeline.
- **Timeline**: largura de cada tile = `duração × pixelsPerSecond`; régua com `CustomPainter`; playhead cruzando todas as faixas com a matemática `posição(ms) / 1000 × pixelsPerSecond`; cabeçalhos de faixa fixos fora do scroll horizontal.
- **Gestos**: tocar no clipe = selecionar + `seekToClip`; long-press = reordenar (`LongPressDraggable`/`DragTarget`); tocar na régua = seek; alças de trim só no clipe selecionado, com largura visual temporária durante o arrasto.
- **Erros**: uma status bar única alimentada por `controller.error`; capture também os erros do `stateStream`.

## 12. Armadilhas comuns

| Sintoma | Causa | Correção |
|---|---|---|
| Tela preta pausada no iOS | Frame inicial não entregue | Já resolvido no plugin (seek de tolerância zero); verifique se o `Texture` usa o `textureId` certo |
| Preview "pulando" ao arrastar playhead | Seek assíncrono confirmando posição antiga | Mantenha `_dragPosition` local durante o gesto |
| Editor travando ao arrastar slider de volume/velocidade | Chamando o nativo a cada tick | Commit só em `onChangeEnd`/release |
| Export sem áudio externo | Usou `exportTimeline(clips)` | Use `exportCurrentTimeline()` |
| `StateError` ao abrir tela de export | Acessou `exportProgress` fora de export | Escute o stream só na janela do export |
| Thumbnails repetidos/antigos após editar | Cache de requisições não invalidado | Limpe o mapa de futures a cada mutação |
| `load` falhando com asset | Passou caminho de asset | Copie para arquivo temporário antes |
| Undo habilitado mas não funciona | Só olhou `state.canUndo` (ou só o local) | Exija os dois: `state.canUndo && controller.canUndo` |
| Split no fim do clipe não faz nada | `atLocalPosition >= duração` | Trate como no-op na UI (o plugin também ignora) |
| Timeline "crescendo" ao adicionar áudio | Esperava que a trilha estendesse a duração | Por design: áudio é capado pela duração dos clipes |

## 13. Testes

- **Player com platform fake**: injete `NativeTimelinePlayer(platform: fake)` e teste validações (`ArgumentError`, `StateError`) e delegação sem tocar o nativo.
- **Payloads do channel**: teste `MethodChannelVideoUltraPlayer` com `TestDefaultBinaryMessenger` assertando método + argumentos (ms, não `Duration`).
- **Widget tests do editor**: monte a tela com `autoLoad: false` e verifique o shell (toolbar, placeholders, botões desabilitados sem timeline) — sem device.

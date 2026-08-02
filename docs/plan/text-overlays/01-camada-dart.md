# Text Overlays na Timeline — Parte 1: Camada Dart

> **Objetivo da parte:** Modelo `TimelineTextOverlay` serializável + métodos `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` federados no platform interface, method channel e `NativeTimelinePlayer`, com testes passando.
> **Plano:** `00-indice.md` (Design de Origem, contrato do modelo, ordem e dependências)
> **Depende de:** nenhuma

## Contexto

Toda capacidade do plugin é federada nas quatro camadas e a API pública nunca instancia `MethodChannel`. O padrão de referência é `AudioTrack`: modelo imutável em `lib/src/models/` com `toJson` em milissegundos, assinatura no `VideoUltraPlayerPlatform` recebendo `Map<String, dynamic>`, implementação em `MethodChannelVideoUltraPlayer` e wrapper com validação em `NativeTimelinePlayer`.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models/timeline_text_overlay.dart` | criar | Modelo imutável: campos, asserts, `toJson`, `copyWith`, igualdade |
| `lib/video_ultra_player.dart` | editar | Exportar o novo modelo no barrel |
| `lib/video_ultra_player_platform_interface.dart` | editar | 3 assinaturas novas (`textureId` + map / id) |
| `lib/video_ultra_player_method_channel.dart` | editar | `invokeMethod` de `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` |
| `lib/src/native_timeline_player.dart` | editar | Wrappers públicos com `_requireTextureId()` |
| `test/timeline_text_overlay_test.dart` | criar | Testes do modelo (espelhar `test/audio_track_test.dart`) |
| `test/native_timeline_player_test.dart` | editar | Delegação com fake platform + StateError sem load |
| `test/video_ultra_player_method_channel_test.dart` | editar | Payload exato no channel |

## Fases

### Fase 1 — Testes (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar `test/timeline_text_overlay_test.dart` espelhando a estrutura de `test/audio_track_test.dart`:
  - `toJson` serializa todos os campos: `id`, `text`, `startMs`, `endMs`, `x`, `y`, `rotationDegrees`, `fontSize`, `color`, `backgroundColor`, `opacity`, `textAlign` (string)
  - `toJson` omite `fontFamily`/`fontPath` quando `null`
  - asserts: `x`/`y` em `[0, 1]`, `fontSize` em `(0, 1]`, `opacity` em `[0, 1]` (lançam `AssertionError` em debug)
  - `copyWith` substitui campos e preserva os não passados
  - igualdade: duas instâncias com mesmos campos são `==`; campo diferente quebra igualdade
  - > **Drift registrado:** o assert `end > start` foi **removido** do contrato de testes — comparação de `Duration` não é expressão const em Dart (`const_eval_type_num`), impossível num construtor `const`. A exigência segue documentada no doc comment do modelo e é responsabilidade do app/nativo. (Verificado: Dart 3.12.2.)
- [x] Em `test/native_timeline_player_test.dart`, adicionar no `_FakeVideoUltraPlayerPlatform` os métodos `addTextOverlay`/`updateTextOverlay`/`removeTextOverlay` registrando em `calls` (padrão de `setAudioTrack`, linha ~245), e grupo de testes:
  - os 3 métodos lançam `StateError` antes de `load`
  - após `load`, `addTextOverlay` chama a plataforma com `textureId` e o mapa serializado
  - `updateTextOverlay` idem; `removeTextOverlay` envia o `id` correto
- [x] Em `test/video_ultra_player_method_channel_test.dart`, adicionar testes de payload (padrão `setAudioTrack sends correct payload`, linha ~351):
  - `addTextOverlay` envia método `'addTextOverlay'` com `{textureId, overlay}`
  - `updateTextOverlay` envia `'updateTextOverlay'` com `{textureId, overlay}`
  - `removeTextOverlay` envia `'removeTextOverlay'` com `{textureId, overlayId}`
- [x] Verificação: `flutter test` compila e os testes novos falham por `UnimplementedError`/classe inexistente — não por erro de sintaxe

### Fase 2 — Modelo `TimelineTextOverlay`

- [x] Criar `lib/src/models/timeline_text_overlay.dart` seguindo o estilo de `audio_track.dart` (`@immutable`, construtor `const`, doc comments em inglês):
  - Campos: `id` (String), `text` (String), `start`/`end` (Duration), `x`/`y` (double), `rotationDegrees` (double, default 0), `fontSize` (double), `color` (int ARGB, default `0xFFFFFFFF`), `fontFamily` (String?), `fontPath` (String?), `backgroundColor` (int ARGB, default `0x00000000`), `opacity` (double, default 1.0), `textAlign` (enum `TimelineTextAlign { left, center, right }`, default `center`)
  - Asserts no construtor conforme contrato do índice (exceto ordenação de `Duration` — ver drift na Fase 1)
  - `toJson()`: durações em ms (`startMs`, `endMs`), `textAlign` como `name`, opcionais omitidos quando `null`
  - `copyWith`, `operator ==`, `hashCode` cobrindo todos os campos
- [x] Adicionar `export 'package:video_ultra_player/src/models/timeline_text_overlay.dart';` em `lib/video_ultra_player.dart` (ordem alfabética, antes de `timeline_player_state.dart`)
- [x] Verificação: `test/timeline_text_overlay_test.dart` passa (`flutter test test/timeline_text_overlay_test.dart`)

### Fase 3 — Federação Dart (interface → channel → player)

- [x] Em `lib/video_ultra_player_platform_interface.dart`, adicionar seção `// ── Text overlays ──` (após a seção de áudio) com:
  - `Future<void> addTextOverlay(int textureId, Map<String, dynamic> overlay)`
  - `Future<void> updateTextOverlay(int textureId, Map<String, dynamic> overlay)`
  - `Future<void> removeTextOverlay(int textureId, String overlayId)`
  - Todas lançando `UnimplementedError` por padrão, com doc comments no estilo existente
- [x] Em `lib/video_ultra_player_method_channel.dart`, implementar os 3 métodos com `methodChannel.invokeMethod<void>`: `addTextOverlay`/`updateTextOverlay` com `<String, Object?>{'textureId': textureId, 'overlay': overlay}` e `removeTextOverlay` com `{'textureId': textureId, 'overlayId': overlayId}`
- [x] Em `lib/src/native_timeline_player.dart`, adicionar seção `// ── Text overlays ──` (após a seção de áudio) com wrappers públicos que chamam `_requireTextureId()` e delegam (`overlay.toJson()`), com doc comments: exige `load`, lança `StateError` caso contrário; `updateTextOverlay` casa por `TimelineTextOverlay.id`
- [x] Verificação: `flutter analyze` limpo e `flutter test` verde (incluindo os testes das fases 1 e 2)
- [x] Checkpoint: commit das mudanças da parte + informar o usuário que a parte 1 está concluída e a parte 2 está pronta para execução

## Critérios de Sucesso

- [ ] `flutter analyze` sem issues
- [ ] Todos os testes unitários passando (`flutter test`)
- [ ] Os 3 métodos existem nas 3 camadas Dart com payload idêntico ao contrato do índice
- [ ] _(manual — feito pelo usuário)_ N/A nesta parte (nativo ainda não implementado)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Divergir do contrato de chaves aprovado (ex.: `endMs` vs `durationMs`) | Baixa | Testes de payload travam as chaves exatas; contrato está no `00-indice.md` |
| `copyWith` não permitir limpar `fontFamily`/`fontPath` (problema clássico de nullable) | Média | Aceitar a limitação (mesmo padrão de `AudioTrack`); usuário cria nova instância se precisar limpar |

## Rollback

Deletar `lib/src/models/timeline_text_overlay.dart` e `test/timeline_text_overlay_test.dart` e reverter as edições nos outros 5 arquivos (`git checkout -- <arquivos>`). Nenhum código existente depende dos novos métodos.

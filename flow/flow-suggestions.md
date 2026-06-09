# Sugestões de Flows a Documentar

> Gerado em 2026-06-09. Execute `/flow <nome>` para criar qualquer um destes flows.

## Flows Sugeridos

### Native Timeline Player (planejado)
**Arquivo a criar:** `flow/native-timeline-player.md`
**Resumo:** Documentaria o caminho completo do player de timeline depois de implementado: `NativeTimelinePlayer` (Dart) → `MethodChannel('video_ultra_player/timeline_player')` / `EventChannel('.../events')` → composição nativa (`AVMutableComposition` no iOS / `CompositionPlayer` no Android) → render para `Texture`. **Aguardando implementação** — ver `plan/native-timeline-player-implementation.md`. Crie este flow ao concluir as Fases 3–6 do plano.

---

### getPlatformVersion (boilerplate atual)
**Arquivo a criar:** `flow/get-platform-version.md`
**Resumo:** Mapearia o stub gerado pelo template: `VideoUltraPlayer.getPlatformVersion()` → `VideoUltraPlayerPlatform.instance` → `MethodChannelVideoUltraPlayer` → `MethodChannel('video_ultra_player')` → handlers Swift/Kotlin. Baixa prioridade — é boilerplate temporário que será substituído pelo timeline player.

## Já documentados

- `flow/project-structure.md` — Estrutura geral do projeto

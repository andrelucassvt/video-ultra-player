# GitHub Copilot Instructions — instructions-ia

Repositório central de instruções de IA da ANL-Software (`ANL-Software/flutter-instructions-ia`). Não é um app — é um hub em Bash + Markdown que distribui skills e arquivos-semente de contexto para três plataformas de IA (Claude Code, GitHub Copilot, Codex/Agents). O payload distribuído ensina Flutter com Clean Architecture, mas este repo não contém código Flutter.

## Stack

- Bash (scripts de sync) + Markdown (conteúdo das instruções)
- Distribuição: `git clone --depth 1` → `rsync -a --delete`
- `skills-lock.json` rastreia skills importadas de terceiros (ex.: `flutter-adaptive-ui`)

## Estrutura

- `.claude/skills/` — **fonte de verdade** das 15 skills (catálogo distribuído)
- `.github/prompts/` — prompts: `setup-project-context`, `audit_setup`
- `.github/skills/`, `.agents/skills/` — espelhos read-only de `.claude/skills/`
- `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md` — arquivos-semente distribuídos só-se-ausente
- `docs/flow/` — documentação dos flows deste repo (local, **não** distribuída pelo sync)
- `sync-instructions.sh`, `sync-brain.sh` — scripts de distribuição

## Comandos

- `./sync-instructions.sh` — sincroniza tudo (skills + sementes) para as 3 plataformas; auto-atualiza o próprio script
- `./sync-brain.sh` — sincroniza o conjunto de raciocínio e entrega (`brainstorming`, `flow`, `flow-init`, `writing-plan`, `executing-plan`)

## Convenções

- Editar skill: sempre em `.claude/skills/<skill>/` — nunca nos espelhos `.github/skills/` ou `.agents/skills/` (são sobrescritos pelo `rsync --delete`)
- Skills externas: ao importar de terceiros, registre origem + hash em `skills-lock.json`
- Frontmatter de skill (`name`, `description`) dispara a ativação — descrições precisam de triggers explícitos
- Idioma do conteúdo: português

## Gotchas

- **Arquivos-semente (`CLAUDE.md`/`AGENTS.md`/`copilot-instructions.md`) são templates distribuídos**, não doc descartável: o `sync-instructions.sh` os copia para projetos destino só se ausentes (`if [ ! -f ]`). Reescrevê-los aqui re-semeia todos os consumidores.
- `rsync --delete` é destrutivo: qualquer arquivo local ausente na origem é apagado nos espelhos
- `sync-instructions.sh` substitui a si mesmo pela versão de origem ao final, sem revisão nem checksum
- Drift conhecido: `AGENTS.md` e `README.md` historicamente listaram skills inexistentes em `.claude/skills/` e referenciaram um `architecture.instructions.md` ausente — não há mais pasta de rules; regras obrigatórias antigas viraram guidance dentro das skills `brainstorming` e `flow-init`

## Não fazer

- Não edite os diretórios-espelho (`.github/skills/`, `.agents/skills/`) — edite a fonte em `.claude/`
- Não trate os arquivos-semente como contexto local descartável — eles propagam para downstream
- Não rode os scripts de sync esperando preservar alterações locais nas skills — elas são perdidas
- Não crie arquivos `.md` em `docs/flow/` à mão — use `/flow` ou `/flow-init`

## 📖 Documentação de Flows

Para qualquer feature ou fluxo, verifique a pasta `./docs/flow/`: leia os títulos dos arquivos `.md` disponíveis e, se algum for relevante para a tarefa atual, leia-o antes de implementar ou debugar.

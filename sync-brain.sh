#!/usr/bin/env bash
# sync-brain.sh
# Sincroniza apenas as skills de raciocínio e planejamento para este projeto:
#   skills: brainstorming, flow, flow-init, writing-plan
#   rules:  brainstorming.instructions.md
#
# Uso:
#   chmod +x sync-brain.sh
#   ./sync-brain.sh
#
# Coloque este script na raiz de cada projeto Flutter.
# Pode ser chamado manualmente ou via git hook / CI.

set -euo pipefail

# ============================================================
# CONFIGURAÇÃO — ajuste estas variáveis
# ============================================================

SOURCE_REPO="git@github.com:ANL-Software/flutter-instructions-ia.git"
SOURCE_BRANCH="main"

# ============================================================
# NÃO EDITE ABAIXO (a menos que saiba o que está fazendo)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR=$(mktemp -d)

BRAIN_SKILLS=(brainstorming flow flow-init writing-plan)
BRAIN_RULE="brainstorming.instructions.md"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "⬇️  Clonando instruções mais recentes..."
git clone --depth 1 --branch "$SOURCE_BRANCH" "$SOURCE_REPO" "$TMP_DIR" --quiet

# ── Skills selecionadas ────────────────────────────────────
echo "📁 Sincronizando skills de raciocínio..."

for skill in "${BRAIN_SKILLS[@]}"; do
  SRC="$TMP_DIR/.claude/skills/$skill"
  if [ -d "$SRC" ]; then
    mkdir -p "$SCRIPT_DIR/.claude/skills/$skill"
    rsync -a --delete "$SRC/" "$SCRIPT_DIR/.claude/skills/$skill/"

    mkdir -p "$SCRIPT_DIR/.github/skills/$skill"
    rsync -a --delete "$SRC/" "$SCRIPT_DIR/.github/skills/$skill/"

    mkdir -p "$SCRIPT_DIR/.agents/skills/$skill"
    rsync -a --delete "$SRC/" "$SCRIPT_DIR/.agents/skills/$skill/"

    echo "  ✅ $skill"
  else
    echo "  ⚠️  skill '$skill' não encontrada no repositório fonte. Pulando."
  fi
done

# ── Rule: brainstorming.instructions.md ───────────────────
echo "📋 Sincronizando rule de brainstorming..."

RULE_SRC="$TMP_DIR/.claude/rules/$BRAIN_RULE"
if [ -f "$RULE_SRC" ]; then
  # Claude Code
  mkdir -p "$SCRIPT_DIR/.claude/rules"
  cp "$RULE_SRC" "$SCRIPT_DIR/.claude/rules/$BRAIN_RULE"

  # Codex / Agents — ajusta path de skill
  mkdir -p "$SCRIPT_DIR/.agents/instructions"
  cp "$RULE_SRC" "$SCRIPT_DIR/.agents/instructions/$BRAIN_RULE"
  sed -i '' 's|\.claude/skills/|.agents/skills/|g' "$SCRIPT_DIR/.agents/instructions/$BRAIN_RULE"

  # GitHub Copilot — substitui frontmatter description → applyTo: '**'
  mkdir -p "$SCRIPT_DIR/.github/instructions"
  cp "$RULE_SRC" "$SCRIPT_DIR/.github/instructions/$BRAIN_RULE"
  sed -i '' 's|^description:.*|applyTo: '"'"'**'"'"'|g' "$SCRIPT_DIR/.github/instructions/$BRAIN_RULE"
  sed -i '' 's|\.claude/skills/|.github/skills/|g' "$SCRIPT_DIR/.github/instructions/$BRAIN_RULE"

  echo "  ✅ $BRAIN_RULE"
else
  echo "  ⚠️  '$BRAIN_RULE' não encontrado no repositório fonte. Pulando."
fi

echo ""
echo "✅ Brain sync concluído!"
echo ""
echo "Arquivos atualizados:"

for skill in "${BRAIN_SKILLS[@]}"; do
  echo "  • .claude/skills/$skill"
  echo "  • .github/skills/$skill"
  echo "  • .agents/skills/$skill"
done

echo "  • .claude/rules/$BRAIN_RULE"
echo "  • .github/instructions/$BRAIN_RULE"
echo "  • .agents/instructions/$BRAIN_RULE"

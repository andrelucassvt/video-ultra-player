#!/usr/bin/env bash
# O gauntlet: nenhuma implementação é declarada pronta sem passar por aqui.
# Uso: ./scripts/check.sh          (rápido, para o loop de desenvolvimento)
#      ./scripts/check.sh --full   (inclui métricas e integration test)

set -euo pipefail

MIN_COVERAGE="${MIN_COVERAGE:-80}"
FULL=false
[[ "${1:-}" == "--full" ]] && FULL=true

step() { printf "\n\033[1;34m▸ %s\033[0m\n" "$1"; }
fail() { printf "\n\033[1;31m✗ %s\033[0m\n" "$1"; exit 1; }

step "Formatação"
dart format --set-exit-if-changed lib test || fail "Código fora do formato. Rode: dart format lib test"

step "Análise estática"
flutter analyze --fatal-infos --fatal-warnings || fail "Análise estática falhou."

step "Testes + cobertura"
flutter test --coverage --test-randomize-ordering-seed=random || fail "Testes falharam."

step "Cobertura mínima (${MIN_COVERAGE}%)"
if command -v lcov >/dev/null 2>&1; then
  lcov --remove coverage/lcov.info \
    '**/*.g.dart' '**/*.freezed.dart' '**/*.mocks.dart' '**/generated/**' \
    -o coverage/lcov_clean.info >/dev/null 2>&1
  PCT=$(lcov --summary coverage/lcov_clean.info 2>&1 | grep -oP 'lines\.*: \K[0-9.]+' | head -1)
  echo "Cobertura: ${PCT}%"
  awk -v p="$PCT" -v m="$MIN_COVERAGE" 'BEGIN { exit (p+0 >= m+0) ? 0 : 1 }' \
    || fail "Cobertura ${PCT}% abaixo do mínimo de ${MIN_COVERAGE}%."
else
  echo "lcov não instalado — pulando threshold (brew install lcov / apt install lcov)"
fi

if $FULL; then
  step "Métricas de código"
  dart run dart_code_metrics:metrics analyze lib || fail "Métricas fora do limite."

  step "Dependências não usadas"
  dart run dependency_validator || fail "Problema nas dependências."

  if [ -d integration_test ]; then
    step "Integration tests"
    flutter test integration_test || fail "Integration tests falharam."
  fi
fi

printf "\n\033[1;32m✓ Gauntlet completo — pode declarar pronto.\033[0m\n"

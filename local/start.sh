#!/usr/bin/env bash
# Run RStudio locally: local/start.sh [up|down|logs|status]
set -euo pipefail

cd "$(dirname "$0")"
COMPOSE=(docker compose -p spcs-rstudio -f docker-compose.yml)

case "${1:-up}" in
  up)     "${COMPOSE[@]}" up -d --build --wait
          echo "RStudio: http://127.0.0.1:8787" ;;
  down)   "${COMPOSE[@]}" down ;;
  logs)   "${COMPOSE[@]}" logs -f ;;
  status) "${COMPOSE[@]}" ps ;;
  *)      echo "Usage: $0 [up|down|logs|status]" >&2; exit 1 ;;
esac

#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-tuff-casino}"
[ -d "$ROOT/backend" ] || { echo "Сначала запустите: bash setup-project.sh"; exit 1; }

cat > "$ROOT/backend/Dockerfile" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY backend/package*.json ./
RUN npm install --omit=dev && npm cache clean --force
COPY backend/src ./src
COPY database /database
COPY frontend /frontend
ENV NODE_ENV=production PORT=3000 MIGRATIONS_DIR=/database/migrations
EXPOSE 3000
CMD ["sh", "-c", "node src/migrate.js && node src/server.js"]
EOF

python3 - "$ROOT/docker-compose.yml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
s=s.replace('build: ./backend', 'build:\n      context: .\n      dockerfile: backend/Dockerfile')
p.write_text(s)
PY

python3 - "$ROOT/backend/src/services/game.js" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle="export async function placeBet(userId,input,idempotencyKey){\n  if(input.currency!==config.currency)"
replacement="export async function placeBet(userId,input,idempotencyKey){\n  // Встроенная математика предназначена исключительно для TEST_MODE.\n  // В production замените её сертифицированным game/RNG provider adapter.\n  if(!config.testMode) throw new HttpError(503,'Native game engine is disabled outside TEST_MODE','GAME_PROVIDER_REQUIRED');\n  if(input.currency!==config.currency)"
if needle not in s:
    raise SystemExit('Не найден фрагмент services/game.js — файл уже изменён или патч применён')
s=s.replace(needle,replacement)
p.write_text(s)
PY

cat >> "$ROOT/README.md" <<'EOF'

## Примечание о Docker build context

Docker собирается из корня проекта, чтобы образ мог получить `backend`, `frontend` и `database`:

```yaml
build:
  context: .
  dockerfile: backend/Dockerfile
```

Встроенная игровая математика теперь принудительно работает только при `TEST_MODE=true`. При `TEST_MODE=false` endpoint ставок возвращает `GAME_PROVIDER_REQUIRED`, пока не подключён сертифицированный game/RNG provider.
EOF

echo "Исправления применены к $ROOT"
echo "Запуск: cd $ROOT && cp .env.example .env && docker compose up -d --build"

#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
# в Git для Windows rev-parse даёт C:/..., rsync считает «C:» удалённым узлом; pwd даёт /c/...
LOCAL_DIR="$(cd "$(git rev-parse --show-toplevel)" && pwd)/site/"

DRY_RUN=""
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN="--dry-run" ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует, доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена:" >&2
    git status --short >&2
    exit 1
fi

rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

if [[ -n "${DRY_RUN}" ]]; then
    echo "Пробный запуск: состояние сервера не изменено"
    exit 0
fi

# тайм-ауты: при остановленном nginx в сети WSL соединение не сбрасывается и curl ждал бы бесконечно
if curl -fsS --connect-timeout 5 --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Доставлен коммит $(git rev-parse --short HEAD)"
    exit 0
else
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi

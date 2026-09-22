#!/usr/bin/env bash
# Практика 1, вариант 02 — журнал команд (выполнялись по одной в WSL)

# ---------- 2. Yandex CLI ----------
# curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash
# yc init   # каталог default, зона ru-central1-b

# ---------- 3. Сервисный аккаунт ----------
sudo apt install -y jq
yc iam service-account get --name filin-02-sa >/dev/null 2>&1 || \
  yc iam service-account create --name filin-02-sa
export FOLDER_ID=$(yc config get folder-id)
export SA_ID=$(yc iam service-account get --name filin-02-sa --format json | jq -r .id)
echo "$FOLDER_ID $SA_ID"
yc resource-manager folder add-access-binding "$FOLDER_ID" \
  --role editor \
  --subject "serviceAccount:$SA_ID"
yc iam service-account list
yc resource-manager folder list-access-bindings "$FOLDER_ID"

mkdir -p ~/.yc-keys
if [ ! -s ~/.yc-keys/filin-02-key.json ]; then
  yc iam key create --service-account-name filin-02-sa \
    --output ~/.yc-keys/filin-02-key.json
fi

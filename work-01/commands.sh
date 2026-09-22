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

# ---------- 4. Своя сеть и машина ----------
export PREFIX=filin-02
export ZONE=ru-central1-b
export CIDR=10.12.1.0/24
export DISK_SIZE=20

yc vpc network create --name "$PREFIX-net"
yc vpc subnet create \
  --name "$PREFIX-subnet" \
  --network-name "$PREFIX-net" \
  --zone "$ZONE" \
  --range "$CIDR"
yc vpc subnet list

yc compute instance create \
  --name "$PREFIX-web-1" \
  --hostname "$PREFIX-web-1" \
  --zone "$ZONE" \
  --platform standard-v3 \
  --cores=2 \
  --core-fraction=20 \
  --memory=2 \
  --preemptible \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-2404-lts,type=network-hdd,size="$DISK_SIZE" \
  --network-interface subnet-name="$PREFIX-subnet",nat-ip-version=ipv4 \
  --ssh-key ~/.ssh/id_ed25519.pub \
  --labels created-by=cli

yc compute instance list
export VM_IP=$(yc compute instance get "$PREFIX-web-1" --format json \
  | jq -r '.network_interfaces[0].primary_v4_address.one_to_one_nat.address')
ssh yc-user@"$VM_IP"   # далее nginx и замена текста вручную, как в п. 1.2–1.3

# ---------- 5. Сведения о ресурсах ----------
yc compute instance list
yc compute instance list --format json
yc compute instance list --format json \
  | jq -r '.[] | "\(.name)\t\(.status)\t\(.network_interfaces[0].primary_v4_address.one_to_one_nat.address // "нет")"'
yc compute instance list --format json | jq -r ".[] | select(.name | startswith(\"$PREFIX\")) | .name"
# остановленные машины (прерываемые могут внезапно остановиться)
yc compute instance list --format json | jq -r '.[] | select(.status != "RUNNING") | .name'

# ---------- 6. Уборка (сначала то, что использует сеть) ----------
yc compute instance delete "$PREFIX-web-1"
yc compute instance delete "$PREFIX-web-manual"
yc vpc subnet delete "$PREFIX-subnet"
yc vpc network delete "$PREFIX-net"
yc compute instance list
yc vpc network list
yc compute disk list

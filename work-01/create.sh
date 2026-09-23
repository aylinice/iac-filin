#!/usr/bin/env bash
# Практика 1, вариант 02 — создание стенда самостоятельной части
# Запуск: ./work-01/create.sh   (на пустом каталоге облака)
set -euo pipefail

# ===== Параметры варианта 02 =====
PREFIX="filin-02"
ZONE="ru-central1-b"
CIDR="10.12.1.0/24"
APP_PORT=8006
DISK_SIZE=20
IMAGE_FAMILY="ubuntu-2204-lts"
VM_COUNT=2
SSH_KEY="$HOME/.ssh/id_ed25519.pub"
# =================================

NET="$PREFIX-net"
SUBNET="$PREFIX-subnet"
SG="$PREFIX-sg"

# проверки окружения
command -v yc >/dev/null || { echo "yc не установлен"; exit 1; }
command -v jq >/dev/null || { echo "jq не установлен: sudo apt install -y jq"; exit 1; }
[ -f "$SSH_KEY" ] || { echo "нет ключа $SSH_KEY"; exit 1; }
if yc vpc network get --name "$NET" >/dev/null 2>&1; then
  echo "Сеть $NET уже существует — сначала выполните destroy.sh"; exit 1
fi

echo ">>> Сеть $NET"
yc vpc network create --name "$NET"

echo ">>> Подсеть $SUBNET ($CIDR, $ZONE)"
yc vpc subnet create \
  --name "$SUBNET" \
  --network-name "$NET" \
  --zone "$ZONE" \
  --range "$CIDR"

echo ">>> Группа безопасности $SG: входящие 22 и $APP_PORT, исходящие — все"
yc vpc security-group create \
  --name "$SG" \
  --network-name "$NET" \
  --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=$APP_PORT,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=egress,port=any,protocol=any,v4-cidrs=[0.0.0.0/0]"
SG_ID=$(yc vpc security-group get --name "$SG" --format json | jq -r .id)

for i in $(seq 1 "$VM_COUNT"); do
  VM="$PREFIX-app-$i"
  echo ">>> Машина $VM"
  yc compute instance create \
    --name "$VM" \
    --hostname "$VM" \
    --zone "$ZONE" \
    --platform standard-v3 \
    --cores=2 \
    --core-fraction=20 \
    --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$DISK_SIZE" \
    --network-interface subnet-name="$SUBNET",nat-ip-version=ipv4,security-group-ids="$SG_ID" \
    --ssh-key "$SSH_KEY" \
    --labels created-by=script
done

echo ">>> Стенд готов:"
yc compute instance list --format json \
  | jq -r --arg p "$PREFIX-app-" --arg port "$APP_PORT" \
    '.[] | select(.name | startswith($p)) | "\(.name)\thttp://\(.network_interfaces[0].primary_v4_address.one_to_one_nat.address):\($port)"'

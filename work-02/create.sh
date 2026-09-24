#!/usr/bin/env bash
# Практика 2, вариант 02: сеть, две подсети, группа безопасности, машины по двум зонам,
# доп. диск на первой машине (размечает cloud-init), целевая группа и балансировщик.
# Запуск:  bash work-02/create.sh [ЧИСЛО_МАШИН] [ДИСК_ГБ]
# Без аргументов берутся значения варианта: 3 машины, диск 10 ГБ.
set -euo pipefail            # стоп на первой ошибке и на пустой переменной

# ---- параметры варианта 02 ----
PREFIX=filin-02              # префикс имён ресурсов
ZONE_A=ru-central1-b         # зона A
ZONE_B=ru-central1-d         # зона B
CIDR_A=10.12.1.0/24          # подсеть в зоне A
CIDR_B=10.12.2.0/24          # подсеть в зоне B
APP_PORT=8006                # порт, на котором отвечает nginx
GREETING=cloudlab            # слово на странице
VM_COUNT="${1:-3}"           # 1-й аргумент: число машин (по умолчанию из варианта)
DISK_SIZE="${2:-10}"         # 2-й аргумент: доп. диск, ГБ (по умолчанию из варианта)
BOOT_SIZE=20                 # загрузочный диск, ГБ
IMAGE_FAMILY=ubuntu-2404-lts # образ машин, одинаковый у всех вариантов

cd "$(dirname "$0")/.."      # пути к шаблону относительные: работаем из корня репозитория

# ---- проверки перед запуском ----
if ! [[ "$VM_COUNT" =~ ^[1-9][0-9]*$ && "$DISK_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  echo "Использование: bash work-02/create.sh [ЧИСЛО_МАШИН] [ДИСК_ГБ] (целые > 0)" >&2
  exit 1
fi
# памяти о созданном у скрипта нет, поэтому хотя бы не запускаемся поверх стенда
if yc vpc network get --name "$PREFIX-net" >/dev/null 2>&1; then
  echo "Сеть $PREFIX-net уже есть: стенд поднят. Сначала bash work-02/destroy.sh" >&2
  exit 1
fi
echo "Параметры: машин $VM_COUNT, доп. диск $DISK_SIZE ГБ, порт $APP_PORT, зоны $ZONE_A и $ZONE_B"

echo "==> сеть, подсети и группа безопасности"
yc vpc network create --name "$PREFIX-net"
yc vpc subnet create --name "$PREFIX-subnet-a" --network-name "$PREFIX-net" \
  --zone "$ZONE_A" --range "$CIDR_A"
yc vpc subnet create --name "$PREFIX-subnet-b" --network-name "$PREFIX-net" \
  --zone "$ZONE_B" --range "$CIDR_B"

SG_ID=$(yc vpc security-group create --name "$PREFIX-sg" --network-name "$PREFIX-net" \
  --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=$APP_PORT,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=$APP_PORT,protocol=tcp,v4-cidrs=[198.18.235.0/24,198.18.248.0/24]" \
  --rule "direction=ingress,port=any,protocol=any,v4-cidrs=[$CIDR_A,$CIDR_B]" \
  --rule "direction=egress,port=any,protocol=any,v4-cidrs=[0.0.0.0/0]" \
  --format json | jq -r .id)
echo "группа безопасности $PREFIX-sg: $SG_ID"

echo "==> файл настройки из шаблона"
SSH_KEY=$(cat ~/.ssh/id_ed25519.pub)
export APP_PORT GREETING SSH_KEY
envsubst '${APP_PORT} ${GREETING} ${SSH_KEY}' \
  < work-02/cloud-init.tpl.yaml > work-02/cloud-init.yaml

echo "==> дополнительный диск"
# создаётся до машин: cloud-init разметит его только если диск есть при первой загрузке
yc compute disk create --name "$PREFIX-data" --zone "$ZONE_A" \
  --size "$DISK_SIZE" --type network-hdd

echo "==> машины"
ZONES=("$ZONE_A" "$ZONE_B")
SUBNETS=("$PREFIX-subnet-a" "$PREFIX-subnet-b")

for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))              # 0, 1, 0, 1 ... — чередование зон
  DISK_ARGS=()
  if [ "$i" -eq 1 ]; then             # диск подключается только к первой машине, в зоне A
    DISK_ARGS=(--attach-disk "disk-name=$PREFIX-data,device-name=data")
  fi
  yc compute instance create \
    --name "$PREFIX-app-$i" \
    --zone "${ZONES[$idx]}" \
    --platform standard-v3 \
    --cores=2 --core-fraction=20 --memory=2 \
    --preemptible \
    --create-boot-disk image-folder-id=standard-images,image-family="$IMAGE_FAMILY",type=network-hdd,size="$BOOT_SIZE" \
    --network-interface subnet-name="${SUBNETS[$idx]}",nat-ip-version=ipv4,security-group-ids="$SG_ID" \
    --hostname "$PREFIX-app-$i" \
    --metadata-from-file user-data=work-02/cloud-init.yaml \
    "${DISK_ARGS[@]}"
done

echo "==> целевая группа"
TARGETS=""
for i in $(seq 1 "$VM_COUNT"); do
  idx=$(( (i - 1) % 2 ))
  IP=$(yc compute instance get "$PREFIX-app-$i" --format json \
    | jq -r '.network_interfaces[0].primary_v4_address.address')
  TARGETS="$TARGETS --target subnet-name=${SUBNETS[$idx]},address=$IP"
done
yc load-balancer target-group create --name "$PREFIX-tg" $TARGETS

echo "==> балансировщик"
TG_ID=$(yc load-balancer target-group get --name "$PREFIX-tg" --format json | jq -r .id)
yc load-balancer network-load-balancer create \
  --name "$PREFIX-lb" \
  --region-id ru-central1 \
  --listener name=http,port=80,target-port="$APP_PORT",external-ip-version=ipv4 \
  --target-group target-group-id="$TG_ID",healthcheck-name=http,healthcheck-interval=2s,healthcheck-timeout=1s,healthcheck-unhealthythreshold=2,healthcheck-healthythreshold=2,healthcheck-http-port="$APP_PORT",healthcheck-http-path=/

LB_IP=$(yc load-balancer network-load-balancer get --name "$PREFIX-lb" --format json \
  | jq -r '.listeners[0].address')

# готовность ждём сами: cloud-init ещё ставит nginx, а скрипт об этом не знает
echo "Ждём, пока все машины станут HEALTHY (до 5 минут)..."
OK=0
for t in $(seq 1 30); do
  OK=$(yc load-balancer network-load-balancer target-states --name "$PREFIX-lb" \
    --target-group-id "$TG_ID" | grep -cw HEALTHY || true)
  echo "  через $((t * 10)) с: HEALTHY $OK из $VM_COUNT"
  if [ "$OK" -eq "$VM_COUNT" ]; then break; fi
  sleep 10
done
if [ "$OK" -ne "$VM_COUNT" ]; then
  echo "ВНИМАНИЕ: за 5 минут HEALTHY только $OK из $VM_COUNT — смотрите target-states" >&2
fi
echo "Стенд готов: http://$LB_IP"

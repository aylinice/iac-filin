#!/usr/bin/env bash
# Практика 1, вариант 02 — удаление всего, что создал create.sh
set -uo pipefail

# ===== Параметры варианта 02 =====
PREFIX="filin-02"
VM_COUNT=2
# =================================

NET="$PREFIX-net"
SUBNET="$PREFIX-subnet"
SG="$PREFIX-sg"

# порядок: машины (с дисками) -> группа безопасности -> подсеть -> сеть
for i in $(seq 1 "$VM_COUNT"); do
  VM="$PREFIX-app-$i"
  if yc compute instance get --name "$VM" >/dev/null 2>&1; then
    echo ">>> Удаляю машину $VM"
    yc compute instance delete --name "$VM"
  fi
done

if yc vpc security-group get --name "$SG" >/dev/null 2>&1; then
  echo ">>> Удаляю группу безопасности $SG"
  yc vpc security-group delete --name "$SG"
fi

if yc vpc subnet get --name "$SUBNET" >/dev/null 2>&1; then
  echo ">>> Удаляю подсеть $SUBNET"
  yc vpc subnet delete --name "$SUBNET"
fi

if yc vpc network get --name "$NET" >/dev/null 2>&1; then
  echo ">>> Удаляю сеть $NET"
  yc vpc network delete --name "$NET"
fi

echo ">>> Проверка: машин и дисков быть не должно, из сетей — только default"
yc compute instance list
yc compute disk list
yc vpc network list

#!/usr/bin/env bash
set -euo pipefail            # стоп на первой ошибке и на пустой переменной

PREFIX=filin-02              # префикс варианта 02
VM_COUNT=3

# сначала то, что ссылается на другие ресурсы
yc load-balancer network-load-balancer delete "$PREFIX-lb"
yc load-balancer target-group delete "$PREFIX-tg"

for i in $(seq 1 "$VM_COUNT"); do
  yc compute instance delete "$PREFIX-app-$i"
done

# диск подключён с auto-delete=false и переживает удаление машины
yc compute disk delete "$PREFIX-data"

yc vpc security-group delete "$PREFIX-sg"
yc vpc subnet delete "$PREFIX-subnet-a"
yc vpc subnet delete "$PREFIX-subnet-b"
yc vpc network delete "$PREFIX-net"

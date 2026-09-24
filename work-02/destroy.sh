#!/usr/bin/env bash
# Практика 2, вариант 02: удаляет всё, что создаёт create.sh.
# Работает на любом состоянии стенда: отсутствующее пропускается,
# машины ищутся по префиксу в облаке, а не по числу из скрипта.
set -euo pipefail            # стоп на первой ошибке и на пустой переменной

PREFIX=filin-02              # префикс имён ресурсов варианта 02

# есть ли ресурс: 0 — есть, 1 — нет; любая другая ошибка (сеть, токен) останавливает скрипт,
# в отличие от «delete ... || true», которое проглотило бы и настоящие ошибки
exists() {
  local err
  if err=$("$@" 2>&1 >/dev/null); then
    return 0
  fi
  if grep -qi 'not found' <<< "$err"; then
    return 1
  fi
  echo "Ошибка при проверке ($*): $err" >&2
  exit 1
}

# удалить, если есть:  remove "<группа команд yc>" <имя>
remove() {
  local kind="$1" name="$2"
  if exists yc $kind get --name "$name"; then
    echo "==> удаляю $name"
    yc $kind delete --name "$name"
  else
    echo "--- $name нет, пропускаю"
  fi
}

# сначала то, что ссылается на другие ресурсы
remove "load-balancer network-load-balancer" "$PREFIX-lb"
remove "load-balancer target-group" "$PREFIX-tg"

# машины: спрашиваем облако, какие заведены с нашим префиксом
VMS=$(yc compute instance list --format json \
  | jq -r --arg p "$PREFIX-app-" '.[] | select(.name | startswith($p)) | .name')
if [ -z "$VMS" ]; then
  echo "--- машин $PREFIX-app-* нет, пропускаю"
fi
for vm in $VMS; do
  echo "==> удаляю $vm"
  yc compute instance delete --name "$vm"
done

# диск подключён без автоудаления и переживает машину — удаляется отдельно
remove "compute disk" "$PREFIX-data"
remove "vpc security-group" "$PREFIX-sg"
remove "vpc subnet" "$PREFIX-subnet-a"
remove "vpc subnet" "$PREFIX-subnet-b"
remove "vpc network" "$PREFIX-net"

echo "Готово: ресурсов с префиксом $PREFIX не осталось"

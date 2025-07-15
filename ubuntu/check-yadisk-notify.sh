#!/bin/bash

STATUS=$(yandex-disk status)

if [[ "$STATUS" != "Idle" ]]; then
  notify-send "Yandex Disk" "Текущий статус: $STATUS"
fi

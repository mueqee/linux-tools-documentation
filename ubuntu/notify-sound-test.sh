#тест_звук_уведомление
DISPLAY=:0 \
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
notify-send -i dialog-information "🔔 Уведомление" "Звук сейчас прозвучит" && \
paplay /usr/share/sounds/freedesktop/stereo/complete.oga

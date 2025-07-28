# Linux Tools & Documentation

Коллекция полезных инструментов и документации для работы с Linux-системами, включая Ubuntu и Astra Linux.

## 📁 Структура проекта

```
linux/
├── ubuntu/                    # Инструменты для Ubuntu
│   ├── notify_sound.sh       # Скрипт для тестирования звуковых уведомлений
│   ├── check-yadisk-notify.sh # Мониторинг статуса Yandex.Disk
│   └── mailru-sync-monitor.sh # Мониторинг синхронизации Mail.ru Cloud
├── astralinux/               # Документация по Astra Linux
│   ├── chatGPT_AstraLinux.md # Ссылка на ChatGPT GPT для Astra Linux
│   └── specifications_AstraLinux/ # Техническая документация
│       ├── Vovk_ASTRA-LINUX-Rukovodstvo-po-nacionalnoy-operacionnoy-sisteme-i-sovmestimym-ofisnym-programmam.658698.pdf
│       ├── Burenin_Bezopasnost-operacionnoy-sistemy-specialnogo-naznacheniya-Astra-Linux-Special-Edition.634746.pdf
│       ├── Kompyutery_Operacionnaya-sistema-specialnogo-naznacheniya-ASTRA-LINUX-SPECIAL-EDITION-.660652.pdf
│       ├── Rukovodyashchie-ukazaniya-po-konstruirovaniyu-prikladnogo-programmnogo-obespecheniya-dlya-operacionnoy-sistemy-obshchego-naznacheniya-Astra-Linux-Comm.703049.pdf
│       └── Документация ⬝ Операционная Система Astra Linux Special Edition РУСБ.10015-01 (очередное обновление 1.7)-v6-20250213_003233.docx
└── README.md                 # Этот файл
```

## 🛠️ Ubuntu Tools

### notify_sound.sh
Скрипт для тестирования звуковых уведомлений в Ubuntu.

**Использование:**
```bash
chmod +x ubuntu/notify_sound.sh
./ubuntu/notify_sound.sh
```

**Функции:**
- Отправляет уведомление с иконкой
- Воспроизводит звуковой файл
- Настроен для работы с графической средой

### check-yadisk-notify.sh
Скрипт для мониторинга статуса Yandex.Disk с уведомлениями.

**Использование:**
```bash
chmod +x ubuntu/check-yadisk-notify.sh
./ubuntu/check-yadisk-notify.sh
```

**Функции:**
- Проверяет текущий статус Yandex.Disk
- Отправляет уведомление при изменении статуса
- Полезен для автоматизации в cron

### mailru-sync-monitor.sh
Продвинутый скрипт для мониторинга синхронизации Mail.ru Cloud с подробными уведомлениями.

**Использование:**
```bash
chmod +x ubuntu/mailru-sync-monitor.sh

# Запустить синхронизацию с мониторингом
./ubuntu/mailru-sync-monitor.sh start

# Проверить статус текущей синхронизации
./ubuntu/mailru-sync-monitor.sh status

# Остановить синхронизацию
./ubuntu/mailru-sync-monitor.sh stop

# Просмотреть логи
./ubuntu/mailru-sync-monitor.sh log
```

**Функции:**
- Автоматическая синхронизация указанной директории с Mail.ru Cloud
- Уведомления каждые 5 минут о прогрессе синхронизации
- Отображение времени работы и статуса операции
- Логирование всех операций
- Контроль процесса (запуск/остановка/статус)
- Уведомления о завершении синхронизации (успешное/с ошибкой)

**Конфигурация:**
По умолчанию синхронизирует:
- Источник: `/home/liiilia/Yandex.Disk/lily-is-here/UI`
- Назначение: `/lily-is-here/UI` (Mail.ru Cloud)
- Режим: push (только новые файлы)
- Потоки: 8

## 📚 Astra Linux Documentation

### Техническая документация
Папка `astralinux/specifications_AstraLinux/` содержит официальную документацию:

- **Руководство по национальной ОС** - полное руководство пользователя
- **Безопасность Astra Linux Special Edition** - документы по безопасности
- **Спецификации для компьютеров** - технические требования
- **Руководящие указания по разработке ПО** - стандарты разработки
- **Актуальная документация Special Edition** - последние обновления

### ChatGPT GPT для Astra Linux
Ссылка на специализированный GPT для работы с Astra Linux: [Astra Linux GPT](https://chatgpt.com/g/g-67accfe72f908191ac4ba8854cdbffa8-astra-linux)

## 🚀 Установка и настройка

1. **Клонирование репозитория:**
```bash
git clone <your-repository-url>
cd linux
```

2. **Установка зависимостей для Ubuntu скриптов:**
```bash
# Для уведомлений
sudo apt install libnotify-bin

# Для звука
sudo apt install pulseaudio-utils

# Для Yandex.Disk (если не установлен)
# Следуйте инструкциям на официальном сайте Yandex.Disk

# Для Mail.ru Cloud (если не установлен)
# pip install mailru-cloud-client
```

3. **Настройка прав доступа:**
```bash
chmod +x ubuntu/*.sh
```

4. **Настройка Mail.ru Cloud (для mailru-sync-monitor.sh):**
```bash
# Авторизация в Mail.ru Cloud
mailrucloud auth

# Проверка подключения
mailrucloud ls
```

## 📋 Требования

### Для Ubuntu скриптов:
- Ubuntu 18.04+ или совместимый дистрибутив
- Графическая среда (для уведомлений)
- PulseAudio (для звука)
- Yandex.Disk (для check-yadisk-notify.sh)
- Mail.ru Cloud Client (для mailru-sync-monitor.sh)

### Для документации Astra Linux:
- PDF-ридер для просмотра документации
- Microsoft Word или совместимый редактор для .docx файлов

## 🤝 Вклад в проект

1. Форкните репозиторий
2. Создайте ветку для новой функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте изменения (`git commit -m 'Add amazing feature'`)
4. Отправьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📄 Лицензия

Этот проект распространяется под лицензией MIT. См. файл `LICENSE` для подробностей.

## 📞 Поддержка

Если у вас есть вопросы или предложения:
- Создайте Issue в репозитории
- Обратитесь к документации в папке `astralinux/`

---

**Примечание:** Документация Astra Linux является официальной и может содержать конфиденциальную информацию. Используйте в соответствии с лицензионными соглашениями. 
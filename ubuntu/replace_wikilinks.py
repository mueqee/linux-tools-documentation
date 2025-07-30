import re
from pathlib import Path

# Путь к файлу
file_path = Path("/home/liiilia/opensourse/obsidian/Личное развитие/Инструменты/obsidian.md")

# Регулярное выражение для [[Ссылка]] или [[Ссылка|Алиас]]
wikilink_pattern = re.compile(r"\[\[([^\|\]]+)(?:\|([^\]]+))?\]\]")

# Проверка существования файла
if not file_path.exists():
    print(f"Файл не найден: {file_path}")
    exit(1)

# Чтение содержимого
with open(file_path, "r", encoding="utf-8") as file:
    content = file.read()

# Замена всех [[...]] на обычный текст
def replace_wikilink(match):
    link_target = match.group(1)
    alias = match.group(2)
    return alias if alias else link_target

new_content = wikilink_pattern.sub(replace_wikilink, content)

# Сохраняем результат (можно сделать резервную копию при желании)
with open(file_path, "w", encoding="utf-8") as file:
    file.write(new_content)

print("✅ Все [[ссылки]] заменены на обычный текст.")


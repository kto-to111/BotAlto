#!/bin/bash
set -e  # остановить скрипт при любой ошибке

echo "=== BotAlto Deploy Script (Debian 12) ==="

# --- 1. Обновление системы и установка базовых зависимостей ---
echo "Обновляю пакеты и ставлю базовые зависимости..."
sudo apt-get update
sudo apt-get install -y curl git ca-certificates gnupg

# --- 2. Установка Node.js 20.x (NodeSource) ---
if ! command -v node &> /dev/null; then
  echo "Устанавливаю Node.js..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
  \. "$HOME/.nvm/nvm.sh"
  nvm install 24
else
  echo "Node.js уже установлен: $(node -v)"
fi

echo "Node version: $(node -v)"
echo "npm version: $(npm -v)"

# --- 3. Клонирование форка репозитория ---
REPO_URL="https://github.com/kto-to111/BotAlto.git"
INSTALL_DIR="$HOME/BotAlto"

if [ -d "$INSTALL_DIR" ]; then
  echo "Папка $INSTALL_DIR уже существует, обновляю..."
  cd "$INSTALL_DIR"
  git pull
else
  echo "Клонирую репозиторий..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

# --- 4. Установка зависимостей проекта ---
echo "Устанавливаю зависимости npm..."
npm install

# --- 5. Создание .env с запросом MONGODB_URI ---
ENV_FILE="$INSTALL_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  echo ".env уже существует."
  read -p "Пересоздать .env заново? (y/N): " RECREATE
  if [[ "$RECREATE" != "y" && "$RECREATE" != "Y" ]]; then
    echo "Оставляю существующий .env без изменений."
  else
    rm -f "$ENV_FILE"
  fi
fi

if [ ! -f "$ENV_FILE" ]; then
  echo ""
  echo "--- Настройка .env ---"
  read -p "Введите MONGODB_URI (строка подключения к MongoDB): " MONGODB_URI
  while [ -z "$MONGODB_URI" ]; do
    echo "MONGODB_URI не может быть пустым."
    read -p "Введите MONGODB_URI: " MONGODB_URI
  done

  read -p "Порт сервера (Enter для значения по умолчанию 3000): " PORT
  PORT=${PORT:-3000}

  cat > "$ENV_FILE" <<EOF
MONGODB_URI=${MONGODB_URI}
PORT=${PORT}
EOF

  chmod 600 "$ENV_FILE"
  echo ".env создан по пути $ENV_FILE"
else
  PORT=$(grep '^PORT=' "$ENV_FILE" | cut -d '=' -f2)
  PORT=${PORT:-3000}
fi

# --- 6. Установка pm2 для автозапуска и авто-рестарта ---
if ! command -v pm2 &> /dev/null; then
  echo "Устанавливаю pm2..."
  sudo npm install -g pm2
else
  echo "pm2 уже установлен: $(pm2 -v)"
fi

# --- 7. Запуск сервера через pm2 ---
echo "Запускаю сервер через pm2..."
pm2 delete botalto 2>/dev/null || true
pm2 start Backend/server.js --name botalto
pm2 save

# --- 8. Автозапуск pm2 при перезагрузке сервера ---
echo "Настраиваю автозапуск pm2 при перезагрузке..."
STARTUP_CMD=$(pm2 startup systemd -u "$USER" --hp "$HOME" | tail -n 1)
eval "$STARTUP_CMD"

echo ""
echo "=== Готово! ==="
echo "Сервер запущен на порту $PORT"
echo "Панель доступна: http://<IP_сервера>:$PORT"
echo "Логи: pm2 logs botalto"
echo "Статус: pm2 status"
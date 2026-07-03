#!/bin/bash
set -e

echo "=== BotAlto Deploy Script (Debian 12) ==="

# --- 0. Determine if sudo is needed ---
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  if command -v sudo &> /dev/null; then
    SUDO="sudo"
  else
    echo "Error: not running as root, and sudo is not installed."
    exit 1
  fi
fi

# --- 1. Update system and install base dependencies ---
echo "Updating packages and installing base dependencies..."
$SUDO apt-get update
$SUDO apt-get install -y curl git ca-certificates gnupg

# --- 2. Install Node.js 20.x (NodeSource) ---
if ! command -v node &> /dev/null; then
  echo "Installing Node.js..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | bash
  \. "$HOME/.nvm/nvm.sh"
  nvm install 24
else
  echo "Node.js already installed: $(node -v)"
fi

echo "Node version: $(node -v)"
echo "npm version: $(npm -v)"

# --- 3. Clone your forked repository ---
REPO_URL="https://github.com/kto-to111/BotAlto.git"
INSTALL_DIR="$HOME/BotAlto"

if [ -d "$INSTALL_DIR" ]; then
  echo "Directory $INSTALL_DIR already exists, pulling latest changes..."
  cd "$INSTALL_DIR"
  git pull
else
  echo "Cloning repository..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

# --- 4. Install project dependencies ---
echo "Installing npm dependencies..."
npm install

if [ ! -d "node_modules/mongodb" ]; then
  echo "mongodb module missing, installing explicitly..."
  npm install mongodb
fi

# --- 5. Create .env and prompt for MONGODB_URI ---
ENV_FILE="$INSTALL_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  echo ".env already exists."
  read -p "Recreate .env? (y/N): " RECREATE
  if [[ "$RECREATE" != "y" && "$RECREATE" != "Y" ]]; then
    echo "Keeping existing .env unchanged."
  else
    rm -f "$ENV_FILE"
  fi
fi

if [ ! -f "$ENV_FILE" ]; then
  echo ""
  echo "--- .env setup ---"
  read -p "Enter MONGODB_URI (MongoDB connection string): " MONGODB_URI
  while [ -z "$MONGODB_URI" ]; do
    echo "MONGODB_URI cannot be empty."
    read -p "Enter MONGODB_URI: " MONGODB_URI
  done

  read -p "Server port (press Enter for default 3000): " PORT
  PORT=${PORT:-3000}

  cat > "$ENV_FILE" <<EOF
MONGODB_URI=${MONGODB_URI}
PORT=${PORT}
EOF

  chmod 600 "$ENV_FILE"
  echo ".env created at $ENV_FILE"
else
  PORT=$(grep '^PORT=' "$ENV_FILE" | cut -d '=' -f2)
  PORT=${PORT:-3000}
fi

# --- 6. Install pm2 for auto-restart and startup ---
if ! command -v pm2 &> /dev/null; then
  echo "Installing pm2..."
  $SUDO npm install -g pm2
else
  echo "pm2 already installed: $(pm2 -v)"
fi

# --- 7. Start server via pm2 ---
echo "Starting server via pm2..."
pm2 delete botalto 2>/dev/null || true
pm2 start Backend/server.js --name botalto
pm2 save

# --- 8. Configure pm2 to start on boot ---
echo "Configuring pm2 startup on boot..."
STARTUP_CMD=$(pm2 startup systemd -u "$USER" --hp "$HOME" | grep -E '^(sudo|env)')
if [ -n "$STARTUP_CMD" ]; then
  eval "$STARTUP_CMD"
else
  echo "pm2 startup already configured, skipping."
fi

echo ""
echo "=== Done! ==="
echo "Server is running on port $PORT"
echo "Dashboard: http://<server_IP>:$PORT"
echo "Logs: pm2 logs botalto"
echo "Status: pm2 status"
#!/usr/bin/env bash
set -euo pipefail

# Chorus VPS setup script
# Run as root on a fresh Ubuntu/Debian server
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/dimenwarper/chorus/main/deploy/setup.sh | bash
#   — or —
#   git clone https://github.com/dimenwarper/chorus.git && cd chorus && sudo bash deploy/setup.sh

CHORUS_USER="chorus"
CHORUS_DIR="/opt/chorus"
DATA_DIR="/var/lib/chorus"
CONFIG_DIR="/etc/chorus"
REPO_URL="https://github.com/dimenwarper/chorus.git"

echo "==> Chorus VPS Setup"
echo ""

# --------------------------------------------------------------------------
# 1. System dependencies
# --------------------------------------------------------------------------

echo "==> Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq git curl build-essential autoconf libncurses-dev \
  libssl-dev unzip sqlite3 libsqlite3-dev 2>/dev/null

# --------------------------------------------------------------------------
# 2. Install Erlang + Elixir via asdf (if not present)
# --------------------------------------------------------------------------

if ! command -v elixir &>/dev/null; then
  echo "==> Installing Erlang and Elixir via asdf..."

  if ! command -v asdf &>/dev/null; then
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
    echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
    export PATH="$HOME/.asdf/bin:$HOME/.asdf/shims:$PATH"
    . "$HOME/.asdf/asdf.sh"
  fi

  asdf plugin add erlang 2>/dev/null || true
  asdf plugin add elixir 2>/dev/null || true

  echo "    Installing Erlang (this takes a while)..."
  asdf install erlang 28.0
  asdf global erlang 28.0

  echo "    Installing Elixir..."
  asdf install elixir 1.19.0-otp-28
  asdf global elixir 1.19.0-otp-28

  mix local.hex --force
  mix local.rebar --force
else
  echo "==> Elixir already installed: $(elixir --version | head -1)"
fi

# --------------------------------------------------------------------------
# 3. Install Caddy (reverse proxy with automatic HTTPS)
# --------------------------------------------------------------------------

if ! command -v caddy &>/dev/null; then
  echo "==> Installing Caddy..."
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https 2>/dev/null
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -qq
  apt-get install -y -qq caddy 2>/dev/null
else
  echo "==> Caddy already installed"
fi

# --------------------------------------------------------------------------
# 4. Create chorus user and directories
# --------------------------------------------------------------------------

echo "==> Setting up user and directories..."

id -u "$CHORUS_USER" &>/dev/null || useradd --system --create-home --shell /bin/bash "$CHORUS_USER"

mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$CHORUS_DIR"
chown "$CHORUS_USER:$CHORUS_USER" "$DATA_DIR" "$CHORUS_DIR"

# --------------------------------------------------------------------------
# 5. Clone or update repo
# --------------------------------------------------------------------------

if [ -d "$CHORUS_DIR/.git" ]; then
  echo "==> Updating repo..."
  cd "$CHORUS_DIR"
  sudo -u "$CHORUS_USER" git pull --ff-only
else
  echo "==> Cloning repo..."
  sudo -u "$CHORUS_USER" git clone "$REPO_URL" "$CHORUS_DIR"
  cd "$CHORUS_DIR"
fi

# --------------------------------------------------------------------------
# 6. Build release
# --------------------------------------------------------------------------

echo "==> Building release..."
cd "$CHORUS_DIR"

sudo -u "$CHORUS_USER" bash -c '
  export MIX_ENV=prod
  mix local.hex --force
  mix local.rebar --force
  mix deps.get --only prod
  mix compile
  mix assets.deploy
  mix release --overwrite
'

# --------------------------------------------------------------------------
# 7. Set up config
# --------------------------------------------------------------------------

if [ ! -f "$CONFIG_DIR/env" ]; then
  echo "==> Creating config template at $CONFIG_DIR/env"
  SECRET=$(cd "$CHORUS_DIR" && sudo -u "$CHORUS_USER" mix phx.gen.secret)
  cp "$CHORUS_DIR/deploy/env.example" "$CONFIG_DIR/env"
  sed -i "s|generate-with-mix-phx-gen-secret|$SECRET|" "$CONFIG_DIR/env"
  chmod 600 "$CONFIG_DIR/env"
  echo ""
  echo "    !! IMPORTANT: Edit $CONFIG_DIR/env with your actual values !!"
  echo ""
else
  echo "==> Config already exists at $CONFIG_DIR/env"
fi

# --------------------------------------------------------------------------
# 8. Run migrations
# --------------------------------------------------------------------------

echo "==> Running migrations..."
sudo -u "$CHORUS_USER" bash -c "
  set -a
  source $CONFIG_DIR/env
  set +a
  $CHORUS_DIR/_build/prod/rel/chorus/bin/chorus eval 'Chorus.Release.migrate()'
"

# --------------------------------------------------------------------------
# 9. Install systemd service
# --------------------------------------------------------------------------

echo "==> Installing systemd service..."
cp "$CHORUS_DIR/deploy/chorus.service" /etc/systemd/system/chorus.service
systemctl daemon-reload
systemctl enable chorus

# --------------------------------------------------------------------------
# 10. Summary
# --------------------------------------------------------------------------

echo ""
echo "============================================"
echo "  Chorus setup complete!"
echo "============================================"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Edit /etc/chorus/env with your values:"
echo "     - PHX_HOST (your domain)"
echo "     - GITHUB_CLIENT_ID + GITHUB_CLIENT_SECRET"
echo "     - ADMIN_GITHUB_ID"
echo "     - GITHUB_TOKEN + GITHUB_OWNER (for repo creation)"
echo ""
echo "  2. Configure Caddy for HTTPS:"
echo "     Edit /etc/caddy/Caddyfile:"
echo "       your-domain.com {"
echo "         reverse_proxy localhost:4000"
echo "       }"
echo "     Then: systemctl restart caddy"
echo ""
echo "  3. Start Chorus:"
echo "     systemctl start chorus"
echo ""
echo "  4. Update your GitHub OAuth app callback URL to:"
echo "     https://your-domain.com/auth/github/callback"
echo ""
echo "  Logs: journalctl -u chorus -f"
echo "  Status: systemctl status chorus"
echo ""

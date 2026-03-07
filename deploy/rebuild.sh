#!/usr/bin/env bash
set -euo pipefail

# Rebuild and restart Chorus after code changes.
# Run from the repo root: bash deploy/rebuild.sh

cd "$(dirname "$0")/.."

echo "==> Building..."
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite

echo "==> Migrating..."
set -a
source /etc/chorus/env
set +a
_build/prod/rel/chorus/bin/chorus eval 'Chorus.Release.migrate()'

echo "==> Restarting..."
sudo systemctl restart chorus

echo "==> Done. Status:"
sudo systemctl status chorus --no-pager -l

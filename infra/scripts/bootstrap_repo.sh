#!/usr/bin/env bash
set -euo pipefail

SRC_ROOT="${1:-/home/vagrant}"
DEST_ROOT="${2:-$HOME/infra-repo}"
GITEA_URL="${3:-http://192.168.56.20:3000/vagrant/infra.git}"
GITEA_USER="${GITEA_USER:-}"
GITEA_PASS="${GITEA_PASS:-}"

if [ ! -d "$SRC_ROOT/ansible" ]; then
	echo "Expected Ansible source tree at $SRC_ROOT/ansible" >&2
	echo "Run this on the services VM after provisioning, where Ansible is available at /home/vagrant/ansible." >&2
	exit 1
fi

mkdir -p "$DEST_ROOT"
rm -rf "$DEST_ROOT/ansible"
cp -a "$SRC_ROOT/ansible" "$DEST_ROOT/"
mkdir -p "$DEST_ROOT/ansible/group_vars"

if [ ! -f "$DEST_ROOT/ansible/group_vars/vault.yml" ]; then
	cat > "$DEST_ROOT/ansible/group_vars/vault.yml" <<'EOF'
---
vault_username: "CHANGE_ME_USERNAME"
vault_password: "CHANGE_ME_PASSWORD"
EOF
fi

if [ -n "$GITEA_USER" ] && [ -n "$GITEA_PASS" ]; then
	cd "$DEST_ROOT/ansible"
	if [ ! -d .git ]; then
		git init -b main 2>/dev/null || git init
		git checkout -B main
	fi
	git config user.email "$GITEA_USER"
	git config user.name "${GITEA_USER%%@*}"
	git remote remove origin 2>/dev/null || true
	GITEA_USER_ENCODED="${GITEA_USER//@/%40}"
	git remote add origin "http://${GITEA_USER_ENCODED}:${GITEA_PASS}@192.168.56.20:3000/vagrant/infra.git"
	git add .
	git commit -m "init infra repo"
	git push -u origin main
	echo "Infra repo pushed to Gitea: $GITEA_URL"
else
	echo "Infra repo prepared at: $DEST_ROOT/ansible"
	echo "Next: export GITEA_USER and GITEA_PASS, then rerun to push to Gitea."
fi

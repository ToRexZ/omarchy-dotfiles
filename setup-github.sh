#!/bin/sh

#!/usr/bin/env bash
set -euo pipefail

KEY_NAME="${1:-github}"
KEY_PATH="$HOME/.ssh/$KEY_NAME"
SSH_CONFIG="$HOME/.ssh/config"
SHELL_RC=""
GITHUB_SSH_KEYS_SETTINGS="https://github.com/settings/keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Pick a shell rc file
if [[ -n "${ZSH_VERSION-}" ]] || [[ "${SHELL-}" == *zsh ]]; then
  SHELL_RC="$HOME/.zshrc"
else
  SHELL_RC="$HOME/.bashrc"
fi

ensure_line() {
  local line="$1"
  local file="$2"
  touch "$file"
  grep -Fxq "$line" "$file" || echo "$line" >> "$file"
}

echo "==> 1) SSH key"
if [[ ! -f "$KEY_PATH" ]]; then
  echo "Creating key at $KEY_PATH"
  # No passphrase by default for automation; change "" to prompt if you prefer.
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "$USER@$(hostname)-github"
else
  echo "Key already exists: $KEY_PATH"
fi
chmod 600 "$KEY_PATH"
[[ -f "${KEY_PATH}.pub" ]] && chmod 644 "${KEY_PATH}.pub"

echo "==> 2) ~/.ssh/config entry for github.com"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

# Add/ensure a Host github.com block (simple append if missing)
if ! grep -qE '^\s*Host\s+github\.com\s*$' "$SSH_CONFIG"; then
  cat >> "$SSH_CONFIG" <<EOF

Host github.com
  HostName github.com
  User git
  IdentityFile $KEY_PATH
  IdentitiesOnly yes
EOF
  echo "Added Host github.com block to $SSH_CONFIG"
else
  echo "Host github.com block already present (not modifying)."
fi

echo "==> 3) ssh-agent persistence"
if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
  echo "Using systemd user ssh-agent service"

  mkdir -p "$HOME/.config/systemd/user"

  cat > "$HOME/.config/systemd/user/ssh-agent.service" <<'EOF'
[Unit]
Description=SSH key agent

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=/usr/bin/ssh-agent -D -a $SSH_AUTH_SOCK

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now ssh-agent.service

  # Ensure shells point to the systemd agent socket
  ensure_line 'export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"' "$SHELL_RC"

  # Ensure key is added when a shell starts (silent if agent not available yet)
  ensure_line "ssh-add \"$KEY_PATH\" >/dev/null 2>&1 || true" "$SHELL_RC"

else
  echo "systemd user not available; falling back to shell-managed agent snippet"
  ensure_line 'if [[ -z "${SSH_AUTH_SOCK-}" ]]; then eval "$(ssh-agent -s)" >/dev/null; fi' "$SHELL_RC"
  ensure_line "ssh-add \"$KEY_PATH\" >/dev/null 2>&1 || true" "$SHELL_RC"
fi

echo "==> 4) Optional: convert existing repo origin from HTTPS to SSH (run inside a repo)"
cat <<'TIP'

To convert a repo remote to SSH (run inside the repo):
  git remote set-url origin git@github.com:<USER>/<REPO>.git

If you want, you can make this script do it automatically when run inside a repo.
TIP

echo "==> Done."
echo
echo "Public key to add to GitHub:"
echo "------------------------------------------------------------"
echo "Go to:" ${GITHUB_SSH_KEYS_SETTINGS}
cat "${KEY_PATH}.pub"
echo "------------------------------------------------------------"
echo
echo "After adding the key in GitHub: test with"
echo "  ssh -T git@github.com"


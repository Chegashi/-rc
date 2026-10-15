#!/usr/bin/env bash
# ============================================================================
#  Kali Linux Post-Install Setup
#  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Chegashi/-rc/master/kali-setup.sh)"
# ----------------------------------------------------------------------------
#  Run this AFTER a fresh Kali Linux install. Kali already ships the offensive
#  toolset, so this script focuses on everything else you still want:
#    * full system update on the kali-rolling branch
#    * dev / cloud / container tooling Kali does not install by default
#      (Docker, Node via nvm, Go, Rust, Python tooling, cloud CLIs, gh)
#    * quality-of-life Zsh config on top of Kali's default zsh
#    * desktop tweaks (auto-detects Xfce — Kali's default — or GNOME)
#    * tops up Kali metapackages & keeps tools current (nuclei templates, etc.)
#    * unpacks rockyou + clones SecLists / PayloadsAllTheThings
#
#  USAGE
#    chmod +x kali-setup.sh && ./kali-setup.sh
#
#  Toggle sections with env vars (see "Config defaults"), e.g.:
#    INSTALL_DOCKER=0 INSTALL_CLOUD=0 ./kali-setup.sh
#
#  Run as a regular user (it sudo's where needed). Log out/in afterwards so
#  the docker group and desktop changes take effect.
# ============================================================================
set -eu
if [ -z "${BASH_VERSION:-}" ]; then
  command -v bash >/dev/null 2>&1 && exec bash "$0" "$@"
  echo "[!] Please run with bash."; exit 1
fi
set -o pipefail
export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

# --------------------------- Config defaults -------------------------------
INSTALL_DEV=${INSTALL_DEV:-1}            # compilers, CLI goodies, editors
INSTALL_DOCKER=${INSTALL_DOCKER:-1}      # Docker Engine + compose
INSTALL_NODE=${INSTALL_NODE:-1}          # nvm + Node LTS
INSTALL_GO=${INSTALL_GO:-1}
INSTALL_RUST=${INSTALL_RUST:-1}
INSTALL_PY_TOOLS=${INSTALL_PY_TOOLS:-1}  # pipx + pwntools/ROPgadget etc.
INSTALL_CLOUD=${INSTALL_CLOUD:-1}        # AWS / kubectl / terraform / gh
INSTALL_METAPKGS=${INSTALL_METAPKGS:-0}  # extra kali-tools-* metapackages (large)
INSTALL_RECON_GO=${INSTALL_RECON_GO:-1}  # nuclei/httpx/subfinder/ffuf via go
INSTALL_WORDLISTS=${INSTALL_WORDLISTS:-1}
INSTALL_ZSH_EXTRAS=${INSTALL_ZSH_EXTRAS:-1}
INSTALL_DESKTOP_TWEAKS=${INSTALL_DESKTOP_TWEAKS:-1}
INSTALL_FONTS=${INSTALL_FONTS:-1}
INSTALL_SSH_KEY=${INSTALL_SSH_KEY:-1}

# --------------------------- Helpers ---------------------------------------
info()   { echo -e "\e[34m[INFO]\e[0m $*"; }
success(){ echo -e "\e[32m[OK]\e[0m $*"; }
warn()   { echo -e "\e[33m[WARN]\e[0m $*"; }
error()  { echo -e "\e[31m[ERROR]\e[0m $*"; }
has_cmd(){ command -v "$1" &>/dev/null; }
is_wsl() { grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; }
is_kali(){ [[ -f /etc/os-release ]] && grep -qi 'kali' /etc/os-release; }

require_sudo() {
  [[ $(id -u) -eq 0 ]] && { error "Run as a regular user, not root (it sudo's as needed)."; exit 1; }
  sudo -v
}

RC="$HOME/.zshrc"
append_once() {
  local tag="$1" begin end
  begin="# >>> kali-setup:${tag} >>>"; end="# <<< kali-setup:${tag} <<<"
  touch "$RC"
  grep -qF "$begin" "$RC" && { info "zshrc block '${tag}' already present."; return; }
  { echo ""; echo "$begin"; cat; echo "$end"; } >> "$RC"
}

# Install apt packages one-by-one, tolerating any missing on this release.
apt_opt() {
  local pkg
  for pkg in "$@"; do
    if sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
      echo -e "    \e[32m+\e[0m $pkg"
    else
      echo -e "    \e[33m-\e[0m $pkg (unavailable)"
    fi
  done
}

# Detect desktop environment: xfce | gnome | none
detect_de() {
  local de="${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}"
  if echo "$de" | grep -qi xfce || has_cmd xfconf-query; then echo xfce
  elif echo "$de" | grep -qi gnome || has_cmd gsettings; then echo gnome
  else echo none; fi
}

# --------------------------- Steps -----------------------------------------
update_system() {
  info "Updating Kali (kali-rolling)..."
  sudo apt-get update -y
  sudo apt-get full-upgrade -y
  sudo apt-get --fix-broken install -y || true
  sudo apt-get autoremove -y
  sudo apt-get autoclean -y
}

install_dev() {
  [[ "$INSTALL_DEV" == "1" ]] || { warn "Skipping dev tooling."; return; }
  info "Installing dev tooling & CLI goodies..."
  apt_opt build-essential git curl wget vim neovim tmux stow jq yq tree rsync \
          cmake clang gdb lldb valgrind ccache pkg-config ninja-build \
          ripgrep fd-find bat fzf zoxide eza btop ncdu httpie \
          xclip xsel ffmpeg imagemagick p7zip-full unzip zip \
          ca-certificates gnupg lsb-release apt-transport-https \
          python3-pip python3-venv pipx
  append_once dev-aliases <<'EOF'
# fd/bat Debian names + modern CLI
alias fd='fdfind'
alias bat='batcat'
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
command -v eza >/dev/null && alias ls='eza --group-directories-first'
EOF
}

install_python_tooling() {
  [[ "$INSTALL_PY_TOOLS" == "1" ]] || { warn "Skipping Python tooling."; return; }
  info "Installing Python / exploit-dev tooling (pipx, pwntools, ROPgadget)..."
  has_cmd pipx || sudo apt-get install -y pipx || true
  pipx ensurepath || true
  for p in poetry pre-commit black ruff pwntools ROPgadget; do pipx install "$p" || true; done
  # one_gadget (ruby) + GEF for gdb
  sudo gem install one_gadget 2>/dev/null || warn "one_gadget gem skipped."
  [[ -f "$HOME/.gdbinit-gef.py" ]] || bash -c "$(curl -fsSL https://gef.blah.cat/sh)" 2>/dev/null || warn "GEF skipped."
}

install_docker() {
  [[ "$INSTALL_DOCKER" == "1" ]] || { warn "Skipping Docker."; return; }
  has_cmd docker && { info "Docker already present."; return; }
  info "Installing Docker (Kali repo build of docker.io + compose)..."
  # On Kali/Debian the distro docker.io package is the simplest reliable path.
  apt_opt docker.io docker-compose docker-buildx containerd
  sudo systemctl enable --now docker 2>/dev/null || true
  getent group docker >/dev/null || sudo groupadd docker
  sudo usermod -aG docker "$USER" || true
  append_once docker-aliases <<'EOF'
# Docker helpers
alias dockerstp='docker ps -aq | xargs -r docker stop'
alias dockermc='docker ps -aq | xargs -r docker rm -f'
alias dockermi='docker images -aq | xargs -r docker rmi -f'
alias dockercl='dockerstp; dockermc; dockermi'
EOF
  info "Docker installed — log out/in for the docker group to apply."
}

install_node() {
  [[ "$INSTALL_NODE" == "1" ]] || { warn "Skipping Node.js."; return; }
  if [[ ! -d "$HOME/.nvm" ]]; then
    info "Installing nvm + Node LTS..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install --lts && nvm alias default 'lts/*'
  corepack enable || true
}

install_go() {
  [[ "$INSTALL_GO" == "1" ]] || { warn "Skipping Go."; return; }
  info "Installing Go..."
  apt_opt golang-go
  append_once gopath <<'EOF'
export PATH="$HOME/go/bin:$PATH"
EOF
}

install_rust() {
  [[ "$INSTALL_RUST" == "1" ]] || { warn "Skipping Rust."; return; }
  has_cmd cargo && { info "Rust already present."; return; }
  info "Installing Rust (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  append_once rust <<'EOF'
source "$HOME/.cargo/env"
EOF
}

install_cloud() {
  [[ "$INSTALL_CLOUD" == "1" ]] || { warn "Skipping cloud tooling."; return; }
  info "Installing cloud / devops CLIs (kubectl, helm, terraform, awscli, gh)..."
  apt_opt kubernetes-client helm terraform awscli ansible gh
  # AWS CLI v2 fallback if the apt awscli (v1) isn't preferred
  if ! has_cmd aws; then
    TMPD=$(mktemp -d); pushd "$TMPD" >/dev/null
    ARCH=$(uname -m); U="https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip"
    curl -fsSLO "$U" && unzip -q "$(basename "$U")" && sudo ./aws/install --update || warn "AWS CLI v2 install failed."
    popd >/dev/null; rm -rf "$TMPD"
  fi
}

install_recon_go() {
  [[ "$INSTALL_RECON_GO" == "1" ]] || { warn "Skipping Go recon tools."; return; }
  has_cmd go || { warn "Go missing — skipping ProjectDiscovery suite."; return; }
  info "Installing ProjectDiscovery suite + ffuf via go install..."
  export GOBIN="$HOME/go/bin"; mkdir -p "$GOBIN"
  local tools=(
    github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
    github.com/projectdiscovery/httpx/cmd/httpx@latest
    github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
    github.com/ffuf/ffuf/v2@latest
  )
  for t in "${tools[@]}"; do info "  ${t%@*}"; go install "$t" 2>/dev/null || warn "  failed: $t"; done
  "$GOBIN/nuclei" -update-templates 2>/dev/null || true
}

install_metapackages() {
  [[ "$INSTALL_METAPKGS" == "1" ]] || { warn "Skipping Kali metapackages (INSTALL_METAPKGS=0)."; return; }
  info "Installing extra Kali metapackages (this is large)..."
  apt_opt kali-tools-top10 kali-tools-web kali-tools-passwords \
          kali-tools-information-gathering kali-tools-wireless \
          kali-tools-reverse-engineering kali-tools-exploitation
}

setup_wordlists() {
  [[ "$INSTALL_WORDLISTS" == "1" ]] || { warn "Skipping wordlists."; return; }
  info "Preparing wordlists (rockyou, SecLists, PayloadsAllTheThings)..."
  apt_opt wordlists seclists
  [[ -f /usr/share/wordlists/rockyou.txt.gz ]] && sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz || true
  local wl="$HOME/wordlists"; mkdir -p "$wl"
  [[ -d "$wl/SecLists" ]] || git clone --depth=1 https://github.com/danielmiessler/SecLists.git "$wl/SecLists" || warn "SecLists clone failed."
  [[ -d "$wl/PayloadsAllTheThings" ]] || git clone --depth=1 https://github.com/swisskyrepo/PayloadsAllTheThings.git "$wl/PayloadsAllTheThings" || warn "PayloadsAllTheThings clone failed."
  info "Wordlists in $wl and /usr/share/wordlists."
}

install_fonts() {
  [[ "$INSTALL_FONTS" == "1" ]] || { warn "Skipping fonts."; return; }
  info "Installing dev fonts (Fira Code, JetBrains Mono, Nerd fallback)..."
  apt_opt fonts-firacode fonts-jetbrains-mono fonts-powerline fonts-font-awesome
}

setup_zsh_extras() {
  [[ "$INSTALL_ZSH_EXTRAS" == "1" ]] || { warn "Skipping zsh extras."; return; }
  info "Adding QoL config to Kali's default zsh..."
  # Kali ships zsh + a themed prompt already; we only append, never clobber it.
  append_once qol <<'EOF'
# --- Quality of life ---
export EDITOR=vim
export HISTSIZE=100000
export SAVEHIST=100000
setopt INC_APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS
alias ll='ls -alF'
alias gs='git status'
alias ports='ss -tulpn'
alias myip='curl -s ifconfig.me; echo'
alias serve='python3 -m http.server'
# target scratch dir helper:  target 10.10.10.5
target(){ mkdir -p "$HOME/targets/$1"/{nmap,www,loot,exploits} && cd "$HOME/targets/$1" && echo "scratch: $PWD"; }
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
EOF
}

setup_ssh_key() {
  [[ "$INSTALL_SSH_KEY" == "1" ]] || { warn "Skipping SSH key."; return; }
  [[ -f "$HOME/.ssh/id_ed25519" ]] && { info "SSH key already exists."; return; }
  info "Generating SSH key (ed25519)..."
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -N "" -C "$USER@$(hostname)" -f "$HOME/.ssh/id_ed25519"
  success "SSH public key at $HOME/.ssh/id_ed25519.pub"
}

setup_desktop_tweaks() {
  [[ "$INSTALL_DESKTOP_TWEAKS" == "1" ]] || { warn "Skipping desktop tweaks."; return; }
  is_wsl && { warn "WSL — skipping desktop tweaks."; return; }
  local de; de=$(detect_de)
  case "$de" in
    xfce)
      info "Detected Xfce (Kali default) — applying tweaks..."
      # Power: never sleep while working a lab; show battery; tap-to-click
      xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false 2>/dev/null || true
      xfconf-query -c xfce4-session -p /general/LockCommand -s "xflock4" 2>/dev/null || true
      # Clock format with date + seconds
      xfconf-query -c xfce4-panel -p /plugins/clock/digital-format -s "%a %d %b  %H:%M:%S" 2>/dev/null || true
      # Terminal: bigger scrollback is handy for long tool output
      xfconf-query -c xfce4-terminal -p /scrolling-lines -s 100000 2>/dev/null || true
      success "Xfce tweaks applied (some need a re-login)."
      ;;
    gnome)
      info "Detected GNOME — applying tweaks..."
      gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
      gsettings set org.gnome.desktop.interface show-battery-percentage true 2>/dev/null || true
      gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 12' 2>/dev/null || true
      gsettings set org.gnome.desktop.interface clock-show-seconds true 2>/dev/null || true
      gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
      success "GNOME tweaks applied."
      ;;
    *)
      warn "No supported desktop detected (Xfce/GNOME) — skipping GUI tweaks." ;;
  esac
}

final_summary() {
  success "Kali post-install complete."
  echo "- Log out/in (or reboot) so the docker group and desktop changes apply."
  echo "- Open a new shell to load nvm / cargo / go / pipx into PATH."
  echo "- Wordlists: ~/wordlists and /usr/share/wordlists (rockyou unpacked)."
  echo "- Scratch a target dir with:  target 10.10.10.5"
}

# --------------------------- Main ------------------------------------------
main() {
  require_sudo
  is_kali || { error "This script is intended for Kali Linux."; exit 1; }
  update_system
  install_dev
  install_python_tooling
  install_docker
  install_node
  install_go
  install_rust
  install_cloud
  install_recon_go
  install_metapackages
  setup_wordlists
  install_fonts
  setup_zsh_extras
  setup_ssh_key
  setup_desktop_tweaks
  final_summary
}

main "$@"

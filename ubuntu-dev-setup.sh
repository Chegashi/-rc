#!/usr/bin/env bash
# curl -fsSL https://raw.githubusercontent.com/Chegashi/-rc/master/ubuntu-dev-setup.sh | bash
# ----------------------------------------------------------------------------
# Ubuntu Dev Machine Bootstrapper
#
# Sets up a fresh Ubuntu (Desktop or Server) for development: system updates,
# essential CLI tools, Docker (official repo), Zsh + Oh My Zsh with plugins,
# Conda (Miniconda) with an optional 42AI env, Node.js via nvm, VS Code,
# common IDEs & apps (snap), Kubernetes tools, browsers, and useful extras.
#
# USAGE
#   1) Save this file as ubuntu-dev-setup.sh
#   2) chmod +x ubuntu-dev-setup.sh
#   3) ./ubuntu-dev-setup.sh
#
# Environment toggles (export before running, or prefix the command):
#   HEADLESS=0            # 1 = skip GUI apps/snaps; auto-enabled on WSL
#   INSTALL_IDES=1        # 0 = skip heavy IDEs (PyCharm, Sublime, GitKraken)
#   INSTALL_BROWSERS=1    # 0 = skip Brave/Opera
#   INSTALL_K8S=1         # 0 = skip kubectl/helm/k9s
#   INSTALL_NODE=1        # 0 = skip nvm + Node.js
#   INSTALL_CONDA=1       # 0 = skip Miniconda
#   INSTALL_42AI_ENV=1    # 0 = skip creating conda env 42AI-$USER
#   CONDA_PY_VERSION=3.11 # Python version for the 42AI env
#   ZSH_THEME=robbyrussell # Zsh theme
#
# Notes:
# - On WSL, GUI/snap steps are skipped automatically.
# - After install, log out/in (or reboot) so docker group changes take effect.
# ----------------------------------------------------------------------------
set -eu
[ -n "${BASH_VERSION:-}" ] && set -o pipefail

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

# --------------------------- Config defaults -------------------------------
HEADLESS=${HEADLESS:-0}
INSTALL_IDES=${INSTALL_IDES:-1}
INSTALL_BROWSERS=${INSTALL_BROWSERS:-1}
INSTALL_K8S=${INSTALL_K8S:-1}
INSTALL_MINIKUBE=${INSTALL_MINIKUBE:-1}
INSTALL_NODE=${INSTALL_NODE:-1}
INSTALL_CONDA=${INSTALL_CONDA:-1}
INSTALL_42AI_ENV=${INSTALL_42AI_ENV:-1}
CONDA_PY_VERSION=${CONDA_PY_VERSION:-3.11}
ZSH_THEME=${ZSH_THEME:-robbyrussell}
# Extras (default ON for "install everything")
INSTALL_DEV_EXTRAS=${INSTALL_DEV_EXTRAS:-1}
INSTALL_PY_TOOLS=${INSTALL_PY_TOOLS:-1}
INSTALL_GIT_LFS=${INSTALL_GIT_LFS:-1}
INSTALL_SSH_KEY=${INSTALL_SSH_KEY:-1}
INSTALL_PSQL_CLIENT=${INSTALL_PSQL_CLIENT:-1}
INSTALL_FONTS=${INSTALL_FONTS:-1}
INSTALL_RUST=${INSTALL_RUST:-1}
INSTALL_GO=${INSTALL_GO:-1}
INSTALL_JAVA=${INSTALL_JAVA:-1}
INSTALL_TERRAFORM=${INSTALL_TERRAFORM:-1}
INSTALL_AWS=${INSTALL_AWS:-1}
INSTALL_GCLOUD=${INSTALL_GCLOUD:-1}
INSTALL_AZURE=${INSTALL_AZURE:-1}
INSTALL_UFW=${INSTALL_UFW:-0}
INSTALL_DIRENV=${INSTALL_DIRENV:-1}
# New bundles
INSTALL_DEVOPS=${INSTALL_DEVOPS:-1}
INSTALL_SECURITY=${INSTALL_SECURITY:-1}
INSTALL_DB_GUI=${INSTALL_DB_GUI:-1}
INSTALL_IDEA=${INSTALL_IDEA:-1}
INSTALL_ANDROID=${INSTALL_ANDROID:-0}

# --------------------------- Helper detection ------------------------------
require_sudo() {
  if [[ $(id -u) -eq 0 ]]; then
    echo "[!] Please run this script as a regular user (it will sudo as needed)."
    exit 1
  fi
  sudo -v
}

is_wsl() {
  if grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; then
    return 0
  fi
  return 1
}

is_ubuntu() {
  if [[ -f /etc/os-release ]] && grep -qi 'ubuntu' /etc/os-release; then
    return 0
  fi
  return 1
}

has_cmd() { command -v "$1" &>/dev/null; }

# --------------------------- Logging helpers -------------------------------
info()  { echo -e "\e[34m[INFO]\e[0m $*"; }
success(){ echo -e "\e[32m[SUCCESS]\e[0m $*"; }
warn()  { echo -e "\e[33m[WARN]\e[0m $*"; }
error() { echo -e "\e[31m[ERROR]\e[0m $*"; }

# --------------------------- Core steps ------------------------------------
update_system() {
  info "Updating system packages..."
  sudo apt-get update -y
  sudo apt-get full-upgrade -y
  sudo apt-get --fix-broken install -y || true
  sudo apt-get autoremove -y
  sudo apt-get autoclean -y
}


install_dev_extras() {
  [[ "$INSTALL_DEV_EXTRAS" == "1" ]] || { warn "Skipping dev extras (INSTALL_DEV_EXTRAS=0)."; return; }
  info "Installing developer utilities (ripgrep, fd-find, bat, jq, yq, tmux, cmake, clang, gdb, lldb, valgrind, ccache, pkg-config, ninja)..."
  sudo apt-get install -y \
    ripgrep fd-find bat tree jq yq tmux stow zip unzip rsync \
    net-tools dnsutils iproute2 iputils-ping tldr direnv \
    cmake clang gdb lldb valgrind ccache pkg-config ninja-build
  # Make common aliases for Debian names
  {
    echo ''
    echo '# --- Debian-friendly aliases ---'
    echo "alias fd='fdfind'"
    echo "alias bat='batcat'"
  } >> "$HOME/.zshrc"
}

install_python_tooling() {
  [[ "$INSTALL_PY_TOOLS" == "1" ]] || { warn "Skipping Python tooling (INSTALL_PY_TOOLS=0)."; return; }
  info "Installing Python tooling (pipx + linters/formatters)..."
  sudo apt-get install -y python3-pip python3-venv pipx
  python3 -m pip install --user --upgrade pip setuptools wheel || true
  pipx ensurepath || true
  pipx install poetry || true
  pipx install pre-commit || true
  pipx install black || true
  pipx install ruff || true
  pipx install pipenv || true
  pipx install pyright || true
}

install_git_lfs() {
  [[ "$INSTALL_GIT_LFS" == "1" ]] || { warn "Skipping Git LFS (INSTALL_GIT_LFS=0)."; return; }
  info "Installing Git LFS..."
  sudo apt-get install -y git-lfs
  sudo git lfs install --system || true
}

setup_ssh_key() {
  [[ "$INSTALL_SSH_KEY" == "1" ]] || { warn "Skipping SSH key generation (INSTALL_SSH_KEY=0)."; return; }
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    info "SSH key already exists."
  else
    info "Generating SSH key (ed25519)..."
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -C "$USER@$(hostname)" -f "$HOME/.ssh/id_ed25519"
    chmod 600 "$HOME/.ssh/id_ed25519" && chmod 644 "$HOME/.ssh/id_ed25519.pub"
    success "SSH public key at $HOME/.ssh/id_ed25519.pub"
  fi
}

install_psql_client() {
  [[ "$INSTALL_PSQL_CLIENT" == "1" ]] || { warn "Skipping PostgreSQL client (INSTALL_PSQL_CLIENT=0)."; return; }
  info "Installing PostgreSQL client..."
  sudo apt-get install -y postgresql-client
}

install_fonts() {
  [[ "$INSTALL_FONTS" == "1" ]] || { warn "Skipping dev fonts (INSTALL_FONTS=0)."; return; }
  info "Installing developer fonts (Fira Code, JetBrains Mono)..."
  sudo apt-get install -y fonts-firacode fonts-jetbrains-mono || true
}

install_aws_cli() {
  [[ "$INSTALL_AWS" == "1" ]] || { warn "Skipping AWS CLI (INSTALL_AWS=0)."; return; }
  info "Installing AWS CLI v2..."
  TMPD=$(mktemp -d)
  pushd "$TMPD" >/dev/null
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  else
    URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  fi
  curl -fsSLO "$URL"
  ZIPFILE=$(basename "$URL")
  unzip -q "$ZIPFILE"
  sudo ./aws/install --update
  popd >/dev/null
  rm -rf "$TMPD"
}

install_gcloud() {
  [[ "$INSTALL_GCLOUD" == "1" ]] || { warn "Skipping Google Cloud CLI (INSTALL_GCLOUD=0)."; return; }
  info "Installing Google Cloud SDK..."
  sudo apt-get install -y apt-transport-https ca-certificates gnupg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  sudo apt-get update -y && sudo apt-get install -y google-cloud-cli
}

install_azure_cli() {
  [[ "$INSTALL_AZURE" == "1" ]] || { warn "Skipping Azure CLI (INSTALL_AZURE=0)."; return; }
  info "Installing Azure CLI..."
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  AZ_REPO=$(lsb_release -cs)
  echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y azure-cli
}

install_terraform() {
  [[ "$INSTALL_TERRAFORM" == "1" ]] || { warn "Skipping Terraform (INSTALL_TERRAFORM=0)."; return; }
  info "Installing HashiCorp tools (Terraform, Packer)..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y terraform packer
}

install_rust() {
  [[ "$INSTALL_RUST" == "1" ]] || { warn "Skipping Rust (INSTALL_RUST=0)."; return; }
  info "Installing Rust toolchain (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  echo 'source "$HOME/.cargo/env"' >> "$HOME/.zshrc"
}

install_go() {
  [[ "$INSTALL_GO" == "1" ]] || { warn "Skipping Go (INSTALL_GO=0)."; return; }
  info "Installing Go (golang-go)..."
  sudo apt-get install -y golang-go
}

install_java() {
  [[ "$INSTALL_JAVA" == "1" ]] || { warn "Skipping Java toolchain (INSTALL_JAVA=0)."; return; }
  info "Installing Java (OpenJDK 17, Maven, Gradle)..."
  sudo apt-get install -y openjdk-17-jdk maven gradle
}

install_devops_suite() {
  [[ "$INSTALL_DEVOPS" == "1" ]] || { warn "Skipping DevOps suite (INSTALL_DEVOPS=0)."; return; }
  info "Installing DevOps tooling (Ansible, Vagrant, kustomize helper, gh)..."
  sudo apt-get install -y ansible vagrant
}

install_virtualization() {
  [[ "$INSTALL_DEVOPS" == "1" ]] || return
  info "Installing virtualization tools (KVM/QEMU + virt-manager)..."
  sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
  sudo usermod -aG libvirt,kvm "$USER" || true
}

install_gh_cli() {
  info "Installing GitHub CLI (gh)..."
  if ! has_cmd gh; then
    type -p curl >/dev/null || sudo apt-get install -y curl
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
      sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -y && sudo apt-get install -y gh
  else
    info "GitHub CLI already present."
  fi
}

install_security_suite() {
  [[ "$INSTALL_SECURITY" == "1" ]] || { warn "Skipping security tools (INSTALL_SECURITY=0)."; return; }
  info "Installing security & analysis tools..."
  # Wireshark in noninteractive mode defaults to not allowing non-root captures.
  sudo apt-get install -y wireshark tcpdump nmap nikto sqlmap john hydra hashcat gobuster wfuzz \
    binwalk radare2 strace ltrace gdb
}

install_db_gui_apps() {
  [[ "$INSTALL_DB_GUI" == "1" ]] || { warn "Skipping DB GUIs (INSTALL_DB_GUI=0)."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS mode — skipping DB GUIs."; return; }
  info "Installing database GUIs (DBeaver, Insomnia REST, draw.io, Obsidian)..."
  sudo snap install dbeaver-ce
  sudo snap install insomnia
  sudo snap install drawio
  sudo snap install obsidian
}

install_jetbrains_idea() {
  [[ "$INSTALL_IDEA" == "1" ]] || { warn "Skipping IntelliJ IDEA (INSTALL_IDEA=0)."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS mode — skipping IntelliJ IDEA."; return; }
  info "Installing IntelliJ IDEA Community..."
  sudo snap install intellij-idea-community --classic
}

install_android_studio() {
  [[ "$INSTALL_ANDROID" == "1" ]] || { warn "Skipping Android Studio (INSTALL_ANDROID=0)."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS mode — skipping Android Studio."; return; }
  info "Installing Android Studio..."
  sudo snap install android-studio --classic
}

install_minikube() {
  [[ "$INSTALL_MINIKUBE" == "1" ]] || { warn "Skipping minikube (INSTALL_MINIKUBE=0)."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS mode — skipping minikube."; return; }
  info "Installing minikube..."
  TMPD=$(mktemp -d)
  pushd "$TMPD" >/dev/null
  ARCH=$(dpkg --print-architecture)
  if [[ "$ARCH" == "amd64" ]]; then PKG="minikube_latest_amd64.deb"; else PKG="minikube_latest_${ARCH}.deb"; fi
  curl -fsSLO "https://storage.googleapis.com/minikube/releases/latest/${PKG}"
  sudo dpkg -i "$PKG" || sudo apt-get -f install -y
  popd >/dev/null
  rm -rf "$TMPD"
}

setup_ufw() {
  [[ "$INSTALL_UFW" == "1" ]] || { warn "Skipping UFW firewall (INSTALL_UFW=0)."; return; }
  info "Configuring uncomplicated firewall (UFW)..."
  sudo apt-get install -y ufw
  sudo ufw allow OpenSSH
  sudo ufw --force enable
}

setup_zsh_extras() {
  info "Applying extra Zsh config..."
  {
    echo ''
    echo '# --- PATH & environment ---'
    echo 'export PATH="$HOME/.local/bin:$PATH"'
    echo 'export EDITOR=vim'
    echo ''
    echo '# --- History & shell options ---'
    echo 'export HISTSIZE=100000'
    echo 'export SAVEHIST=100000'
    echo 'setopt INC_APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS'
    echo ''
    echo '# direnv (if installed)'
    echo 'command -v direnv >/dev/null && eval "$(direnv hook zsh)"'
  } >> "$HOME/.zshrc"
}


setup_snap() {
  if is_wsl; then
    warn "WSL detected — skipping snap installs (no systemd by default)."
    HEADLESS=1
    return
  fi
  if ! has_cmd snap; then
    info "Installing snapd..."
    sudo apt-get install -y snapd
  fi
  sudo systemctl enable --now snapd.socket || true
  sudo ln -sf /var/lib/snapd/snap /snap || true
}

install_gui_snaps() {
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS=1 — skipping GUI snaps."; return; }
  info "Installing common GUI apps via snap..."
  # Editors & IDEs
  sudo snap install code --classic
  if [[ "$INSTALL_IDES" == "1" ]]; then
    sudo snap install pycharm-community --classic
    # Uncomment to install Pro instead (license required)
    # sudo snap install pycharm-professional --classic
    sudo snap install sublime-text --classic
    sudo snap install gitkraken --classic || warn "GitKraken snap failed (optional)."
  fi
  # Tools & dev apps
  sudo snap install postman
  sudo snap install slack
  sudo snap install doctl
  sudo snap install hugo
  sudo snap install vlc
  sudo snap install gimp
  sudo snap install libreoffice
  sudo snap install keepassxc
  sudo snap install mysql-shell
  sudo snap install termius-app || true
  sudo snap install bw
  sudo snap install fkill
  sudo snap install tio --classic
  # Printers & utilities
  sudo snap install gutenprint-printer-app || true
  # Browsers
  if [[ "$INSTALL_BROWSERS" == "1" ]]; then
    sudo snap install brave
    sudo snap install opera
  fi
}

install_k8s_tools() {
  [[ "$INSTALL_K8S" == "1" ]] || { warn "Skipping Kubernetes tools (INSTALL_K8S=0)."; return; }
  if is_wsl; then
    warn "WSL detected — installing kubectl via apt as snap may not work."
    sudo apt-get install -y kubectl || warn "kubectl apt install failed; you can install manually later."
  else
    info "Installing kubernetes tooling (kubectl, helm, k9s, kubectx/kubens, kustomize)..."
    sudo snap install kubectl --classic
    sudo snap install helm --classic || warn "helm snap failed (optional)."
    sudo snap install k9s || warn "k9s snap failed (optional)."
    sudo apt-get install -y kubectx || warn "kubectx apt install failed (optional)."
    sudo snap install kustomize || warn "kustomize snap failed (optional)."
  fi
}

install_docker() {
  info "Installing Docker Engine (official apt repo)..."
  # Remove conflicting packages if present
  sudo apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 \
    podman-docker containerd runc || true

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add Docker repo
  ARCH=$(dpkg --print-architecture)
  UB_CODENAME=$(lsb_release -cs)
  echo \
"deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${UB_CODENAME} stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  # Manage without sudo
  if ! getent group docker >/dev/null; then
    sudo groupadd docker
  fi
  sudo usermod -aG docker "$USER"
  info "Docker installed. You'll need to log out/in for group changes to apply."
}

install_node_nvm() {
  [[ "$INSTALL_NODE" == "1" ]] || { warn "Skipping Node.js (INSTALL_NODE=0)."; return; }
  if ! has_cmd curl; then sudo apt-get install -y curl; fi
  if [[ ! -d "$HOME/.nvm" ]]; then
    info "Installing nvm (Node Version Manager)..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # Load nvm for this session
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  info "Installing latest LTS Node.js..."
  nvm install --lts
  nvm alias default 'lts/*'
  corepack enable || true
}

install_miniconda() {
  [[ "$INSTALL_CONDA" == "1" ]] || { warn "Skipping Miniconda (INSTALL_CONDA=0)."; return; }
  if has_cmd conda; then
    info "Conda already present."
  else
    info "Installing Miniconda..."
    TMPD=$(mktemp -d)
    pushd "$TMPD" >/dev/null
    PLATFORM="Linux-x86_64"
    if [[ $(uname -m) == "aarch64" ]]; then PLATFORM="Linux-aarch64"; fi
    INST="Miniconda3-latest-${PLATFORM}.sh"
    curl -fsSLO "https://repo.anaconda.com/miniconda/${INST}"
    bash "$INST" -b -p "$HOME/miniconda3"
    popd >/dev/null
    rm -rf "$TMPD"

    "$HOME/miniconda3/bin/conda" init zsh || true
    "$HOME/miniconda3/bin/conda" init bash || true
    "$HOME/miniconda3/bin/conda" config --set auto_activate_base false
  fi

  if [[ "$INSTALL_42AI_ENV" == "1" ]]; then
    info "Ensuring conda env 42AI-$USER exists (Python ${CONDA_PY_VERSION})..."
    # shellcheck disable=SC1091
    source "$HOME/.bashrc" 2>/dev/null || true
    # shellcheck disable=SC1091
    source "$HOME/.zshrc" 2>/dev/null || true
    if conda info --envs 2>/dev/null | grep -q "42AI-$USER"; then
      success "conda env 42AI-$USER already exists."
    else
      conda update -n base -c defaults conda -y || true
      conda create -n "42AI-$USER" python="${CONDA_PY_VERSION}" -y
      conda run -n "42AI-$USER" python -m pip install -U pip
      conda run -n "42AI-$USER" python -m pip install jupyter numpy pandas pycodestyle
    fi
  fi
}

setup_zsh() {
  info "Setting up Zsh + Oh My Zsh + plugins..."
  if ! has_cmd zsh; then sudo apt-get install -y zsh; fi

  # Oh My Zsh (unattended)
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    info "Oh My Zsh already installed."
  fi

  ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM_DIR/plugins"

  # Plugins: zsh-autosuggestions & zsh-syntax-highlighting
  if [[ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
  fi
  if [[ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
  fi

  # Update ~/.zshrc safely
  if [[ -f "$HOME/.zshrc" ]]; then cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)"; fi

  # Ensure ZSH variable points to Oh My Zsh
  if grep -q '^export ZSH=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i 's|^export ZSH=.*|export ZSH="$HOME/.oh-my-zsh"|' "$HOME/.zshrc"
  else
    echo 'export ZSH="$HOME/.oh-my-zsh"' >> "$HOME/.zshrc"
  fi

  # Set theme
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i "s|^ZSH_THEME=.*|ZSH_THEME=\"$ZSH_THEME\"|" "$HOME/.zshrc"
  else
    echo "ZSH_THEME=\"$ZSH_THEME\"" >> "$HOME/.zshrc"
  fi

  # Set plugins list
  if grep -q '^plugins=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i 's/^plugins=.*/plugins=(git docker kubectl npm zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
  else
    echo 'plugins=(git docker kubectl npm zsh-autosuggestions zsh-syntax-highlighting)' >> "$HOME/.zshrc"
  fi

  # Docker helper aliases (safe if no resources exist)
  {
    echo ''
    echo '# --- Docker helpers ---'
    echo "alias dockerstp='docker ps -aq | xargs -r docker stop'"
    echo "alias dockermc='docker ps -aq | xargs -r docker rm -f'"
    echo "alias dockermi='docker images -aq | xargs -r docker rmi -f'"
    echo "alias dockermvlm='docker volume ls -q | xargs -r docker volume rm'"
    echo "alias dockermnet='docker network ls -q | xargs -r docker network rm'"
    echo "alias dockercl='dockerstp; dockermc; dockermi; dockermvlm; dockermnet'"
  } >> "$HOME/.zshrc"

  # Quality-of-life
  {
    echo ''
    echo '# --- QoL aliases ---'
    echo "alias ll='ls -alF'"
    echo "alias gs='git status'"
    echo "alias k='kubectl'"
  } >> "$HOME/.zshrc"

  # Default shell
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    info "Changing default shell to zsh (you may be prompted for your password)."
    chsh -s "$(command -v zsh)"
  fi
}

final_summary() {
  success "\nAll done!"
  echo "- If Docker was installed, log out/in (or reboot) so 'docker' group takes effect."
  echo "- If you installed Conda, open a new shell to load 'conda' into your PATH."
  echo "- Your ~/.zshrc was updated (backup saved if it existed). Start a new terminal to use zsh."
}

install_base_cli() {
  info "Installing base CLI utilities..."
  sudo apt-get install -y \
    build-essential curl wget git vim zsh unzip ca-certificates gnupg \
    software-properties-common apt-transport-https lsb-release \
    gnome-tweaks htop nmap gnome-system-monitor gnome-clocks synaptic
}


# --------------------------- Main ------------------------------------------
main() {
  require_sudo
  is_ubuntu || { error "This script is intended for Ubuntu."; exit 1; }
  update_system
  install_base_cli
  install_dev_extras
  setup_snap
  install_gui_snaps
  install_k8s_tools
  install_minikube
  install_virtualization
  install_docker
  install_node_nvm
  install_miniconda
  install_python_tooling
  install_git_lfs
  install_psql_client
  install_fonts
  install_terraform
  install_aws_cli
  install_gcloud
  install_azure_cli
  install_devops_suite
  install_gh_cli
  install_security_suite
  install_db_gui_apps
  install_rust
  install_go
  install_java
  install_jetbrains_idea
  install_android_studio
  setup_zsh
  setup_zsh_extras
  setup_ssh_key
  setup_ufw
  final_summary
}

main "$@"

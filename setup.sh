#!/usr/bin/env bash
# ============================================================================
#  Ubuntu Dev / DevOps / Security Workstation Bootstrapper
#
#  One-line install (downloads fully, then runs with the terminal attached so
#  sudo/chsh prompts work — unlike `| sh`, which also can't run this bash script):
#
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Chegashi/-rc/master/setup.sh)"
#    bash -c "$(wget -qO- https://raw.githubusercontent.com/Chegashi/-rc/master/setup.sh)"
# ----------------------------------------------------------------------------
#  One script to turn a freshly installed Ubuntu (Desktop/Server/WSL) into a
#  ready-to-work machine:
#    * system update + base CLI utilities
#    * developer tooling (compilers, debuggers, ripgrep/fd/bat/jq, tmux, ...)
#    * languages & runtimes: Node (nvm), Python (Miniconda + pipx), Rust, Go, Java
#    * containers & cloud: Docker, kubectl/helm/k9s, minikube, Terraform/Packer,
#      AWS / GCloud / Azure CLIs, Ansible, Vagrant, KVM/QEMU, GitHub CLI
#    * security / analysis: nmap, wireshark, tcpdump, nikto, sqlmap, john, hydra,
#      hashcat, gobuster, wfuzz, binwalk, radare2, strace/ltrace, gdb
#    * GUI apps (snap): VS Code, PyCharm, Sublime, Postman, DBeaver, browsers...
#    * Zsh + Oh My Zsh + plugins, dev fonts, SSH key
#    * GNOME desktop theming & tweaks for a clean, modern look
#
#  USAGE
#    chmod +x setup.sh && ./setup.sh
#
#  Everything is modular. Toggle sections with env vars (see "Config defaults").
#  Example:  INSTALL_SECURITY=0 HEADLESS=1 ./setup.sh
#
#  Notes:
#    - Run as a regular user; the script uses sudo only where needed.
#    - On WSL, GUI/snap/GNOME steps are skipped automatically.
#    - Log out/in (or reboot) afterwards so docker group + zsh take effect.
# ============================================================================
set -eu
# This script needs bash (it uses [[ ]], arrays, local). If launched under
# sh/dash (e.g. `curl ... | sh`), re-exec through bash when available.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "[!] Please run with bash:  bash -c \"\$(curl -fsSL <url>)\"" >&2
  exit 1
fi
set -o pipefail

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

# --------------------------- Config defaults -------------------------------
HEADLESS=${HEADLESS:-0}            # 1 = skip all GUI apps / GNOME tweaks
INSTALL_IDES=${INSTALL_IDES:-1}
INSTALL_BROWSERS=${INSTALL_BROWSERS:-1}
INSTALL_K8S=${INSTALL_K8S:-1}
INSTALL_MINIKUBE=${INSTALL_MINIKUBE:-1}
INSTALL_NODE=${INSTALL_NODE:-1}
INSTALL_CONDA=${INSTALL_CONDA:-1}
INSTALL_42AI_ENV=${INSTALL_42AI_ENV:-1}
CONDA_PY_VERSION=${CONDA_PY_VERSION:-3.11}
ZSH_THEME=${ZSH_THEME:-robbyrussell}
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
INSTALL_HARDENING=${INSTALL_HARDENING:-0}   # 1 = ClamAV + disable guest/user list
INSTALL_DIRENV=${INSTALL_DIRENV:-1}
INSTALL_DEVOPS=${INSTALL_DEVOPS:-1}
INSTALL_SECURITY=${INSTALL_SECURITY:-1}        # broad Kali-equivalent apt toolset
INSTALL_METASPLOIT=${INSTALL_METASPLOIT:-1}    # Metasploit Framework (Rapid7 repo)
INSTALL_EXPLOIT_DEV=${INSTALL_EXPLOIT_DEV:-1}  # pwntools, gef, ROPgadget, checksec (42 pwn/reverse projects)
INSTALL_WORDLISTS=${INSTALL_WORDLISTS:-1}      # rockyou + SecLists + PayloadsAllTheThings
INSTALL_RECON_GO=${INSTALL_RECON_GO:-1}        # ProjectDiscovery suite (nuclei/httpx/subfinder) + ffuf
INSTALL_BURP_ZAP=${INSTALL_BURP_ZAP:-1}        # OWASP ZAP (free Burp alternative) + Ghidra
INSTALL_DB_GUI=${INSTALL_DB_GUI:-1}
INSTALL_DESKTOP_APPS=${INSTALL_DESKTOP_APPS:-1}  # chat/media/productivity apps
INSTALL_CHROME=${INSTALL_CHROME:-1}              # Google Chrome (.deb)
INSTALL_FLATPAK=${INSTALL_FLATPAK:-1}            # enable Flatpak + Flathub
INSTALL_IDEA=${INSTALL_IDEA:-1}
INSTALL_ANDROID=${INSTALL_ANDROID:-0}
# Desktop look & feel
INSTALL_GNOME_TWEAKS=${INSTALL_GNOME_TWEAKS:-1}
GTK_COLOR_SCHEME=${GTK_COLOR_SCHEME:-dark}   # dark | light

# --------------------------- Detection helpers -----------------------------
require_sudo() {
  if [[ $(id -u) -eq 0 ]]; then
    echo "[!] Please run this script as a regular user (it will sudo as needed)."
    exit 1
  fi
  sudo -v
}
is_wsl()    { grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null; }
is_ubuntu() { [[ -f /etc/os-release ]] && grep -qi 'ubuntu' /etc/os-release; }
has_cmd()   { command -v "$1" &>/dev/null; }

# --------------------------- Logging helpers -------------------------------
info()   { echo -e "\e[34m[INFO]\e[0m $*"; }
success(){ echo -e "\e[32m[SUCCESS]\e[0m $*"; }
warn()   { echo -e "\e[33m[WARN]\e[0m $*"; }
error()  { echo -e "\e[31m[ERROR]\e[0m $*"; }

# Append stdin to ~/.zshrc exactly once, wrapped in a named marker block so the
# script is safe to re-run (idea borrowed from maintainable setup repos — avoids
# the classic "aliases appended five times" bug).
RC="$HOME/.zshrc"
append_once() {
  local tag="$1" begin end
  begin="# >>> setup.sh:${tag} >>>"
  end="# <<< setup.sh:${tag} <<<"
  touch "$RC"
  if grep -qF "$begin" "$RC"; then
    info "zshrc block '${tag}' already present — skipping."
    return
  fi
  { echo ""; echo "$begin"; cat; echo "$end"; } >> "$RC"
}

# Install apt packages one-by-one, tolerating any that don't exist on this
# Ubuntu release (tool names differ across versions / universe availability).
apt_opt() {
  local pkg
  for pkg in "$@"; do
    if sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
      echo -e "    \e[32m+\e[0m $pkg"
    else
      echo -e "    \e[33m-\e[0m $pkg (unavailable on this release)"
    fi
  done
}

# --------------------------- Core steps ------------------------------------
update_system() {
  info "Updating system packages..."
  sudo apt-get update -y
  sudo apt-get full-upgrade -y
  sudo apt-get --fix-broken install -y || true
  sudo apt-get autoremove -y
  sudo apt-get autoclean -y
}

install_base_cli() {
  info "Installing base CLI utilities..."
  sudo apt-get install -y \
    build-essential curl wget git vim zsh unzip ca-certificates gnupg \
    software-properties-common apt-transport-https lsb-release \
    htop nmap synaptic \
    || warn "Some base packages failed — continuing."
}

install_dev_extras() {
  [[ "$INSTALL_DEV_EXTRAS" == "1" ]] || { warn "Skipping dev extras."; return; }
  info "Installing developer utilities (ripgrep, fd, bat, jq, yq, tmux, cmake, clang, gdb, ...)."
  sudo apt-get install -y \
    ripgrep fd-find bat tree jq tmux stow zip unzip rsync \
    net-tools dnsutils iproute2 iputils-ping direnv \
    cmake clang gdb lldb valgrind ccache pkg-config ninja-build \
    || warn "Some core dev packages failed — continuing."
  info "Installing modern CLI goodies (neovim, fzf, zoxide, eza, httpie, tldr, ...)."
  # Tolerant: these vary by Ubuntu release (e.g. tldr/eza/dust may be absent).
  apt_opt yq tldr tealdeer neovim fzf zoxide eza bat-extras ncdu duf dust gdu btop \
          httpie xclip xsel wl-clipboard entr watch aria2 p7zip-full unrar \
          gnupg pass pwgen caca-utils ffmpeg imagemagick
  append_once debian-aliases <<'EOF'
# Debian-friendly aliases
alias fd='fdfind'
alias bat='batcat'
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
command -v eza >/dev/null && alias ls='eza --group-directories-first'
EOF
}

install_python_tooling() {
  [[ "$INSTALL_PY_TOOLS" == "1" ]] || { warn "Skipping Python tooling."; return; }
  info "Installing Python tooling (pipx + linters/formatters)..."
  sudo apt-get install -y python3-pip python3-venv pipx \
    || { warn "pipx not packaged on this release — installing via pip."; \
         sudo apt-get install -y python3-pip python3-venv; \
         python3 -m pip install --user pipx || true; }
  python3 -m pip install --user --upgrade pip setuptools wheel || true
  pipx ensurepath || true
  for pkg in poetry pre-commit black ruff pipenv pyright; do pipx install "$pkg" || true; done
}

install_git_lfs() {
  [[ "$INSTALL_GIT_LFS" == "1" ]] || { warn "Skipping Git LFS."; return; }
  info "Installing Git LFS..."
  sudo apt-get install -y git-lfs
  sudo git lfs install --system || true
}

setup_ssh_key() {
  [[ "$INSTALL_SSH_KEY" == "1" ]] || { warn "Skipping SSH key generation."; return; }
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
  [[ "$INSTALL_PSQL_CLIENT" == "1" ]] || { warn "Skipping PostgreSQL client."; return; }
  info "Installing PostgreSQL client..."
  sudo apt-get install -y postgresql-client
}

install_fonts() {
  [[ "$INSTALL_FONTS" == "1" ]] || { warn "Skipping dev fonts."; return; }
  info "Installing developer fonts (Fira Code, JetBrains Mono)..."
  sudo apt-get install -y fonts-firacode fonts-jetbrains-mono || true
}

install_aws_cli() {
  [[ "$INSTALL_AWS" == "1" ]] || { warn "Skipping AWS CLI."; return; }
  info "Installing AWS CLI v2..."
  TMPD=$(mktemp -d); pushd "$TMPD" >/dev/null
  ARCH=$(uname -m)
  if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  else
    URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  fi
  curl -fsSLO "$URL"; unzip -q "$(basename "$URL")"
  sudo ./aws/install --update
  popd >/dev/null; rm -rf "$TMPD"
}

install_gcloud() {
  [[ "$INSTALL_GCLOUD" == "1" ]] || { warn "Skipping Google Cloud CLI."; return; }
  info "Installing Google Cloud SDK..."
  sudo apt-get install -y apt-transport-https ca-certificates gnupg
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | \
    sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  sudo apt-get update -y && sudo apt-get install -y google-cloud-cli
}

install_azure_cli() {
  [[ "$INSTALL_AZURE" == "1" ]] || { warn "Skipping Azure CLI."; return; }
  info "Installing Azure CLI..."
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y azure-cli
}

install_terraform() {
  [[ "$INSTALL_TERRAFORM" == "1" ]] || { warn "Skipping Terraform."; return; }
  info "Installing HashiCorp tools (Terraform, Packer)..."
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y terraform packer
}

install_rust() {
  [[ "$INSTALL_RUST" == "1" ]] || { warn "Skipping Rust."; return; }
  info "Installing Rust toolchain (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  append_once rust <<'EOF'
source "$HOME/.cargo/env"
EOF
}

install_go() {
  [[ "$INSTALL_GO" == "1" ]] || { warn "Skipping Go."; return; }
  info "Installing Go (golang-go)..."
  sudo apt-get install -y golang-go
}

install_java() {
  [[ "$INSTALL_JAVA" == "1" ]] || { warn "Skipping Java toolchain."; return; }
  info "Installing Java (OpenJDK 17, Maven, Gradle)..."
  apt_opt openjdk-17-jdk openjdk-21-jdk default-jdk maven gradle
}

install_devops_suite() {
  [[ "$INSTALL_DEVOPS" == "1" ]] || { warn "Skipping DevOps suite."; return; }
  info "Installing DevOps tooling (Ansible, Vagrant)..."
  apt_opt ansible vagrant
}

install_virtualization() {
  [[ "$INSTALL_DEVOPS" == "1" ]] || return
  is_wsl && { warn "WSL — skipping virtualization."; return; }
  info "Installing virtualization tools (KVM/QEMU + virt-manager)..."
  # qemu-kvm was renamed/split on newer Ubuntu (qemu-system-x86). Tolerant install
  # so a renamed or missing package doesn't abort the whole script.
  apt_opt qemu-kvm qemu-system-x86 qemu-system qemu-utils \
          libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager
  sudo usermod -aG libvirt,kvm "$USER" 2>/dev/null || true
}

install_gh_cli() {
  info "Installing GitHub CLI (gh)..."
  if has_cmd gh; then info "GitHub CLI already present."; return; fi
  type -p curl >/dev/null || sudo apt-get install -y curl
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh
}

install_security_suite() {
  [[ "$INSTALL_SECURITY" == "1" ]] || { warn "Skipping security tools."; return; }
  info "Installing Kali-equivalent pentest toolset from Ubuntu universe..."
  sudo add-apt-repository -y universe 2>/dev/null || true
  sudo apt-get update -y || true

  info "  [Information gathering]"
  apt_opt nmap masscan dnsenum dnsrecon fierce theharvester recon-ng whatweb \
          dmitry netdiscover enum4linux smbclient nbtscan onesixtyone snmp \
          dnsutils whois sslscan sslyze wafw00f

  info "  [Vulnerability / web app analysis]"
  apt_opt nikto sqlmap wapiti skipfish wfuzz dirb gobuster ffuf feroxbuster \
          commix dotdotpwn cadaver

  info "  [Password attacks]"
  apt_opt john hydra hashcat hashid hash-identifier crunch cewl medusa patator \
          chntpw ncrack

  info "  [Sniffing / spoofing / MITM]"
  # Wireshark: allow non-root captures without the interactive debconf prompt.
  echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
  apt_opt wireshark tshark tcpdump ettercap-graphical dsniff bettercap mitmproxy \
          driftnet macchanger

  info "  [Wireless]"
  apt_opt aircrack-ng reaver wifite kismet hcxtools hcxdumptool pixiewps bully mdk4

  info "  [Reverse engineering / forensics]"
  apt_opt radare2 gdb ltrace strace binwalk foremost sleuthkit testdisk \
          steghide outguess stegsnow binutils nasm apktool dex2jar \
          libimage-exiftool-perl checksec

  info "  [Exploitation / pivoting / utils]"
  apt_opt proxychains4 netcat-traditional socat ncat openvpn tor torsocks \
          exploitdb seclists || true

  success "Base pentest toolset installed. Run specific tools with sudo where needed."
}

install_metasploit() {
  [[ "$INSTALL_METASPLOIT" == "1" ]] || { warn "Skipping Metasploit."; return; }
  if has_cmd msfconsole; then info "Metasploit already present."; return; fi
  info "Installing Metasploit Framework (official Rapid7 apt repo)..."
  curl -fsSL https://apt.metasploit.com/metasploit-framework.gpg.key | \
    sudo gpg --dearmor -o /usr/share/keyrings/metasploit.gpg 2>/dev/null || \
    { warn "Metasploit key fetch failed; skipping."; return; }
  echo "deb [signed-by=/usr/share/keyrings/metasploit.gpg] https://apt.metasploit.com/ lucid main" | \
    sudo tee /etc/apt/sources.list.d/metasploit-framework.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y metasploit-framework || \
    warn "Metasploit install failed (optional)."
}

install_exploit_dev() {
  [[ "$INSTALL_EXPLOIT_DEV" == "1" ]] || { warn "Skipping exploit-dev tooling."; return; }
  info "Installing CTF / exploit-dev tooling (pwntools, gef, ROPgadget, one_gadget)..."
  apt_opt python3-pip python3-dev gdb gdbserver ruby ruby-dev
  # pwntools + ROPgadget via pipx (isolated, on PATH)
  has_cmd pipx || sudo apt-get install -y pipx || true
  pipx install pwntools 2>/dev/null || pip3 install --user pwntools --break-system-packages 2>/dev/null || true
  pipx install ROPgadget 2>/dev/null || pip3 install --user ROPgadget --break-system-packages 2>/dev/null || true
  # GEF: a modern gdb enhancement (works with the 42 reverse projects)
  if [[ ! -f "$HOME/.gdbinit-gef.py" ]]; then
    bash -c "$(curl -fsSL https://gef.blah.cat/sh)" 2>/dev/null || warn "GEF install skipped."
  fi
  # one_gadget (ruby gem, handy for libc exploitation)
  sudo gem install one_gadget 2>/dev/null || warn "one_gadget gem skipped."
}

install_wordlists() {
  [[ "$INSTALL_WORDLISTS" == "1" ]] || { warn "Skipping wordlists."; return; }
  info "Installing wordlists (rockyou, SecLists, PayloadsAllTheThings)..."
  apt_opt wordlists seclists
  # Ensure rockyou is unpacked (apt ships it gzip'd)
  [[ -f /usr/share/wordlists/rockyou.txt.gz ]] && sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz || true
  local wl="$HOME/wordlists"
  mkdir -p "$wl"
  [[ -d "$wl/SecLists" ]] || git clone --depth=1 https://github.com/danielmiessler/SecLists.git "$wl/SecLists" || warn "SecLists clone failed."
  [[ -d "$wl/PayloadsAllTheThings" ]] || git clone --depth=1 https://github.com/swisskyrepo/PayloadsAllTheThings.git "$wl/PayloadsAllTheThings" || warn "PayloadsAllTheThings clone failed."
  info "Wordlists in $wl and /usr/share/wordlists."
}

install_recon_go() {
  [[ "$INSTALL_RECON_GO" == "1" ]] || { warn "Skipping Go recon tools."; return; }
  has_cmd go || { warn "Go not installed — skipping ProjectDiscovery suite."; return; }
  info "Installing ProjectDiscovery suite + ffuf via 'go install'..."
  export GOBIN="$HOME/go/bin"; mkdir -p "$GOBIN"
  local tools=(
    github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
    github.com/projectdiscovery/httpx/cmd/httpx@latest
    github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
    github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
    github.com/ffuf/ffuf/v2@latest
    github.com/OJ/gobuster/v3@latest
  )
  for t in "${tools[@]}"; do
    info "  go install ${t%@*}..."
    go install "$t" 2>/dev/null || warn "  install failed: $t"
  done
  append_once gobin <<'EOF'
export PATH="$HOME/go/bin:$PATH"
EOF
  has_cmd nuclei && nuclei -update-templates 2>/dev/null || true
}

install_db_gui_apps() {
  [[ "$INSTALL_DB_GUI" == "1" ]] || { warn "Skipping DB GUIs."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping DB GUIs."; return; }
  info "Installing DB GUIs & notes (DBeaver, Insomnia, draw.io, Obsidian)..."
  for s in dbeaver-ce insomnia drawio obsidian; do sudo snap install "$s" || warn "$s snap failed."; done
}

install_jetbrains_idea() {
  [[ "$INSTALL_IDEA" == "1" ]] || { warn "Skipping IntelliJ IDEA."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping IntelliJ IDEA."; return; }
  info "Installing IntelliJ IDEA Community..."
  sudo snap install intellij-idea-community --classic
}

install_android_studio() {
  [[ "$INSTALL_ANDROID" == "1" ]] || { warn "Skipping Android Studio."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping Android Studio."; return; }
  info "Installing Android Studio..."
  sudo snap install android-studio --classic
}

install_minikube() {
  [[ "$INSTALL_MINIKUBE" == "1" ]] || { warn "Skipping minikube."; return; }
  info "Installing minikube..."
  TMPD=$(mktemp -d); pushd "$TMPD" >/dev/null
  ARCH=$(dpkg --print-architecture)
  PKG="minikube_latest_${ARCH}.deb"
  curl -fsSLO "https://storage.googleapis.com/minikube/releases/latest/${PKG}"
  sudo dpkg -i "$PKG" || sudo apt-get -f install -y
  popd >/dev/null; rm -rf "$TMPD"
}

setup_ufw() {
  [[ "$INSTALL_UFW" == "1" ]] || { warn "Skipping UFW firewall."; return; }
  info "Configuring firewall (UFW)..."
  sudo apt-get install -y ufw
  sudo ufw allow OpenSSH
  sudo ufw --force enable
}

setup_hardening() {
  [[ "$INSTALL_HARDENING" == "1" ]] || { warn "Skipping hardening (INSTALL_HARDENING=0)."; return; }
  is_wsl && { warn "WSL — skipping desktop hardening."; return; }
  info "Applying basic hardening (ClamAV + GDM login tweaks)..."
  # On-demand antivirus scanner (freshclam updates signatures).
  sudo apt-get install -y clamav clamav-freshclam || warn "ClamAV install failed (optional)."
  sudo systemctl stop clamav-freshclam 2>/dev/null || true
  sudo freshclam || warn "freshclam update failed (will retry on its timer)."
  sudo systemctl start clamav-freshclam 2>/dev/null || true
  # Hide the user list and disable the guest session at the GDM greeter via a
  # dconf drop-in (datacustodian's approach — edits a drop-in, not the main db).
  if [[ -d /etc/dconf/db/gdm.d ]] || sudo mkdir -p /etc/dconf/db/gdm.d 2>/dev/null; then
    sudo tee /etc/dconf/db/gdm.d/00-login-security >/dev/null <<'EOF'
[org/gnome/login-screen]
disable-user-list=true
EOF
    sudo dconf update || warn "dconf update failed."
  fi
  success "Hardening applied."
}

setup_snap() {
  if is_wsl; then
    warn "WSL detected — skipping snap (no systemd by default)."
    HEADLESS=1; return
  fi
  has_cmd snap || { info "Installing snapd..."; sudo apt-get install -y snapd; }
  sudo systemctl enable --now snapd.socket || true
  sudo ln -sf /var/lib/snapd/snap /snap || true
}

install_gui_snaps() {
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping GUI snaps."; return; }
  info "Installing common GUI apps via snap..."
  sudo snap install code --classic
  if [[ "$INSTALL_IDES" == "1" ]]; then
    sudo snap install pycharm-community --classic
    sudo snap install sublime-text --classic
    sudo snap install gitkraken --classic || warn "GitKraken snap failed (optional)."
  fi
  for s in postman slack doctl hugo vlc gimp libreoffice keepassxc mysql-shell bw fkill; do
    sudo snap install "$s" || warn "$s snap failed (optional)."
  done
  sudo snap install tio --classic || true
  sudo snap install termius-app || true
  sudo snap install gutenprint-printer-app || true
  if [[ "$INSTALL_BROWSERS" == "1" ]]; then
    sudo snap install brave || warn "brave snap failed."
    sudo snap install opera || warn "opera snap failed."
  fi
  if [[ "$INSTALL_BURP_ZAP" == "1" ]]; then
    info "Installing GUI security tools (OWASP ZAP, Ghidra, Wireshark GUI)..."
    sudo snap install zaproxy --classic || warn "ZAP snap failed (optional)."
    sudo snap install ghidra || warn "Ghidra snap failed (optional)."
    # Burp Suite Community has no official snap/apt package — grab the installer:
    warn "Burp Suite Community: download from https://portswigger.net/burp/releases (no apt/snap package)."
  fi
}

install_flatpak() {
  [[ "$INSTALL_FLATPAK" == "1" ]] || { warn "Skipping Flatpak."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping Flatpak."; return; }
  is_wsl && { warn "WSL — skipping Flatpak."; return; }
  info "Enabling Flatpak + Flathub (so you can grab anything not on snap/apt)..."
  sudo apt-get install -y flatpak gnome-software-plugin-flatpak || warn "Flatpak install failed."
  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
}

install_chrome() {
  [[ "$INSTALL_CHROME" == "1" ]] || { warn "Skipping Google Chrome."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping Chrome."; return; }
  is_wsl && { warn "WSL — skipping Chrome."; return; }
  has_cmd google-chrome && { info "Chrome already present."; return; }
  [[ "$(dpkg --print-architecture)" == "amd64" ]] || { warn "Chrome .deb is amd64 only — skipping."; return; }
  info "Installing Google Chrome (official .deb)..."
  TMPD=$(mktemp -d); pushd "$TMPD" >/dev/null
  curl -fsSLO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  sudo apt-get install -y ./google-chrome-stable_current_amd64.deb || sudo apt-get -f install -y
  popd >/dev/null; rm -rf "$TMPD"
}

install_desktop_apps() {
  [[ "$INSTALL_DESKTOP_APPS" == "1" ]] || { warn "Skipping extra desktop apps."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping extra desktop apps."; return; }
  is_wsl && { warn "WSL — skipping extra desktop apps."; return; }
  info "Installing everyday desktop apps (chat, media, notes, remote, screenshots)..."
  # Communication
  for s in discord telegram-desktop signal-desktop thunderbird whatsapp-for-linux; do
    sudo snap install "$s" || warn "$s snap failed (optional)."
  done
  # Media & creative
  for s in spotify obs-studio blender inkscape krita audacity vlc; do
    sudo snap install "$s" || warn "$s snap failed (optional)."
  done
  sudo snap install blender --classic 2>/dev/null || true
  # Productivity / notes / remote / screenshots
  for s in joplin-desktop bitwarden standard-notes; do
    sudo snap install "$s" || warn "$s snap failed (optional)."
  done
  apt_opt flameshot remmina okular gnome-boxes transmission-gtk
  # Terminals & extra dev apps
  for s in alacritty; do sudo snap install "$s" --classic || warn "$s snap failed (optional)."; done
  apt_opt kitty tmux neovim
}

install_k8s_tools() {
  [[ "$INSTALL_K8S" == "1" ]] || { warn "Skipping Kubernetes tools."; return; }
  if is_wsl; then
    warn "WSL — installing kubectl via apt."
    sudo apt-get install -y kubectl || warn "kubectl apt install failed."
    return
  fi
  info "Installing kubernetes tooling (kubectl, helm, k9s, kubectx, kustomize)..."
  sudo snap install kubectl --classic
  sudo snap install helm --classic || warn "helm snap failed (optional)."
  sudo snap install k9s || warn "k9s snap failed (optional)."
  sudo apt-get install -y kubectx || warn "kubectx apt install failed (optional)."
  sudo snap install kustomize || warn "kustomize snap failed (optional)."
}

install_docker() {
  info "Installing Docker Engine (official apt repo)..."
  sudo apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 \
    podman-docker containerd runc || true
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  getent group docker >/dev/null || sudo groupadd docker
  sudo usermod -aG docker "$USER"
  info "Docker installed. Log out/in for group changes to apply."
}

install_node_nvm() {
  [[ "$INSTALL_NODE" == "1" ]] || { warn "Skipping Node.js."; return; }
  has_cmd curl || sudo apt-get install -y curl
  if [[ ! -d "$HOME/.nvm" ]]; then
    info "Installing nvm..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  info "Installing latest LTS Node.js..."
  nvm install --lts
  nvm alias default 'lts/*'
  corepack enable || true
}

install_miniconda() {
  [[ "$INSTALL_CONDA" == "1" ]] || { warn "Skipping Miniconda."; return; }
  if has_cmd conda; then
    info "Conda already present."
  else
    info "Installing Miniconda..."
    TMPD=$(mktemp -d); pushd "$TMPD" >/dev/null
    PLATFORM="Linux-x86_64"
    [[ $(uname -m) == "aarch64" ]] && PLATFORM="Linux-aarch64"
    INST="Miniconda3-latest-${PLATFORM}.sh"
    curl -fsSLO "https://repo.anaconda.com/miniconda/${INST}"
    bash "$INST" -b -p "$HOME/miniconda3"
    popd >/dev/null; rm -rf "$TMPD"
    "$HOME/miniconda3/bin/conda" init zsh || true
    "$HOME/miniconda3/bin/conda" init bash || true
    "$HOME/miniconda3/bin/conda" config --set auto_activate_base false
  fi
  if [[ "$INSTALL_42AI_ENV" == "1" ]]; then
    info "Ensuring conda env 42AI-$USER (Python ${CONDA_PY_VERSION})..."
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
  has_cmd zsh || sudo apt-get install -y zsh
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    info "Oh My Zsh already installed."
  fi
  ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM_DIR/plugins"
  [[ -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ]] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
  [[ -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ]] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"

  [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)"

  if grep -q '^export ZSH=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i 's|^export ZSH=.*|export ZSH="$HOME/.oh-my-zsh"|' "$HOME/.zshrc"
  else
    echo 'export ZSH="$HOME/.oh-my-zsh"' >> "$HOME/.zshrc"
  fi
  if grep -q '^ZSH_THEME=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i "s|^ZSH_THEME=.*|ZSH_THEME=\"$ZSH_THEME\"|" "$HOME/.zshrc"
  else
    echo "ZSH_THEME=\"$ZSH_THEME\"" >> "$HOME/.zshrc"
  fi
  if grep -q '^plugins=' "$HOME/.zshrc" 2>/dev/null; then
    sed -i 's/^plugins=.*/plugins=(git docker kubectl npm zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
  else
    echo 'plugins=(git docker kubectl npm zsh-autosuggestions zsh-syntax-highlighting)' >> "$HOME/.zshrc"
  fi
  append_once aliases <<'EOF'
# --- Docker helpers ---
alias dockerstp='docker ps -aq | xargs -r docker stop'
alias dockermc='docker ps -aq | xargs -r docker rm -f'
alias dockermi='docker images -aq | xargs -r docker rmi -f'
alias dockermvlm='docker volume ls -q | xargs -r docker volume rm'
alias dockermnet='docker network ls -q | xargs -r docker network rm'
alias dockercl='dockerstp; dockermc; dockermi; dockermvlm; dockermnet'
# --- QoL aliases ---
alias ll='ls -alF'
alias gs='git status'
alias k='kubectl'
EOF
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    info "Changing default shell to zsh."
    chsh -s "$(command -v zsh)" || warn "chsh failed; change shell manually."
  fi
}

setup_zsh_extras() {
  info "Applying extra Zsh config..."
  append_once env-extras <<'EOF'
# --- PATH & environment ---
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=vim
# --- History & shell options ---
export HISTSIZE=100000
export SAVEHIST=100000
setopt INC_APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS
# direnv (if installed)
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
EOF
}

# --------------------------- Desktop look & feel ---------------------------
setup_gnome_tweaks() {
  [[ "$INSTALL_GNOME_TWEAKS" == "1" ]] || { warn "Skipping GNOME tweaks."; return; }
  [[ "$HEADLESS" == "1" ]] && { warn "HEADLESS — skipping GNOME tweaks."; return; }
  is_wsl && { warn "WSL — skipping GNOME tweaks."; return; }
  has_cmd gsettings || { warn "No GNOME (gsettings) found — skipping desktop tweaks."; return; }

  info "Installing GNOME tweak tools, extensions & icon/cursor themes..."
  sudo apt-get install -y \
    gnome-tweaks gnome-shell-extensions gnome-shell-extension-manager \
    gnome-system-monitor gnome-clocks dconf-editor dconf-cli \
    papirus-icon-theme fonts-firacode fonts-jetbrains-mono \
    ubuntu-restricted-extras file-roller || warn "Some GNOME packages failed (optional)."

  # Force English XDG user dirs (~/Downloads etc.) regardless of system locale
  # (borrowed from my_ubuntu_setup) so paths in scripts/aliases stay predictable.
  LANG=C xdg-user-dirs-update --force 2>/dev/null || true

  # Snapshot current desktop settings before we touch anything, so this machine's
  # look can be fully restored/replayed later (idea from ubuntu-tweaks' gsettings
  # dump).  Restore with:  dconf load / < <file>   or  GNOME_RESTORE_FROM=<file> ./setup.sh
  if has_cmd dconf; then
    local snap="$HOME/gnome-settings-backup-$(date +%Y%m%d-%H%M%S).dconf"
    dconf dump / > "$snap" 2>/dev/null && info "Saved current GNOME settings to $snap"
  fi
  if [[ -n "${GNOME_RESTORE_FROM:-}" && -f "${GNOME_RESTORE_FROM}" ]]; then
    info "Restoring GNOME settings from ${GNOME_RESTORE_FROM} and skipping preset tweaks..."
    dconf load / < "${GNOME_RESTORE_FROM}" && { success "GNOME settings restored."; return; }
    warn "Restore failed — falling back to preset tweaks."
  fi

  info "Applying a clean, modern GNOME look (color scheme, fonts, dock, behaviour)..."
  # Prefer dark/light mode
  if [[ "$GTK_COLOR_SCHEME" == "dark" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark' || true
  else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru' || true
  fi
  # Icons & cursor
  gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' || true
  gsettings set org.gnome.desktop.interface cursor-theme 'Yaru' || true
  # Fonts
  gsettings set org.gnome.desktop.interface font-name 'Ubuntu 11' || true
  gsettings set org.gnome.desktop.interface document-font-name 'Ubuntu 11' || true
  gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 12' || true
  gsettings set org.gnome.desktop.interface font-antialiasing 'rgba' || true
  gsettings set org.gnome.desktop.interface font-hinting 'slight' || true
  # Window buttons: minimize, maximize, close
  gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' || true
  # Clock & calendar niceties
  gsettings set org.gnome.desktop.interface clock-show-weekday true || true
  gsettings set org.gnome.desktop.interface clock-show-seconds true || true
  gsettings set org.gnome.desktop.calendar show-weekdate true || true
  # Tap-to-click + natural scroll
  gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true || true
  gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true || true
  # Nautilus: list view + tree
  gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view' || true
  gsettings set org.gnome.nautilus.list-view use-tree-view true || true

  # Ubuntu Dock (Ubuntu's default GNOME shell) — bottom, auto-hide, compact
  if gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.shell.extensions.dash-to-dock'; then
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' || true
    gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40 || true
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false || true
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide true || true
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true || true
    gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false || true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-trash false || true
    gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize' || true
  fi

  # Keyboard & top-bar niceties (inspired by the mutan gist): show battery %,
  # a Home-folder shortcut, and faster keyboard repeat.
  gsettings set org.gnome.desktop.interface show-battery-percentage true || true
  gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30 || true
  gsettings set org.gnome.desktop.peripherals.keyboard delay 250 || true
  # Super+E opens the file manager (Home)
  gsettings set org.gnome.settings-daemon.plugins.media-keys home "['<Super>e']" || true
  # Workspaces: a fixed set of 4, handy for tiling
  gsettings set org.gnome.mutter dynamic-workspaces false || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 || true

  success "GNOME tweaks applied. Some changes appear after logging out/in."
}

final_summary() {
  success "\nAll done!"
  echo "- If Docker was installed, log out/in (or reboot) so 'docker' group takes effect."
  echo "- Open a new shell to load conda/nvm/zsh into your PATH."
  echo "- GNOME look changes fully apply after logging out/in."
  echo "- Your ~/.zshrc was updated (backup saved if it existed)."
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
  install_flatpak
  install_chrome
  install_desktop_apps
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

  install_rust
  install_go
  install_java

  install_security_suite
  install_metasploit
  install_exploit_dev
  install_wordlists
  install_recon_go
  install_db_gui_apps
  install_jetbrains_idea
  install_android_studio

  setup_zsh
  setup_zsh_extras
  setup_ssh_key
  setup_ufw
  setup_hardening
  setup_gnome_tweaks

  final_summary
}

main "$@"

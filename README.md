# Ubuntu Dev / DevOps / Security Workstation Bootstrapper

One script — [`setup.sh`](setup.sh) — that turns a freshly installed Ubuntu
(Desktop, Server, or WSL) into a ready-to-work machine: developer tooling,
languages, containers & cloud, security/analysis tools, GUI apps, a configured
Zsh, and a clean modern GNOME desktop.

## Quick start

```sh
git clone https://github.com/Chegashi/-rc.git && cd -rc
chmod +x setup.sh && ./setup.sh
```

Or straight from the web (one line):

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Chegashi/-rc/master/setup.sh)"
```

No `curl`? Use `wget`:

```sh
bash -c "$(wget -qO- https://raw.githubusercontent.com/Chegashi/-rc/master/setup.sh)"
```

> **Why not `curl … | sh`?** This is a bash script, and `/bin/sh` on Ubuntu is
> `dash` (no `[[ ]]`, arrays, or `local`). Piping also hands the shell's stdin to
> `curl`, so the `sudo`/`chsh` password prompts can't read your keyboard. The
> `bash -c "$(…)"` form downloads the whole script first, then runs it with the
> terminal still attached. (If you do pipe it to `sh`, the script re-execs itself
> under `bash` when possible, or exits with instructions.)

Run it as a **regular user** (it calls `sudo` only where needed). On WSL, all
GUI / snap / GNOME steps are skipped automatically.

## What it installs

| Area | Tools |
|------|-------|
| Base CLI | build-essential, git, vim, curl/wget, htop, zsh, synaptic |
| Dev extras | ripgrep, fd, bat, jq, yq, tmux, cmake, clang, gdb/lldb, valgrind, ninja |
| Languages | Node (nvm), Python (Miniconda + pipx: poetry/ruff/black/pyright), Rust, Go, Java (JDK 17, Maven, Gradle) |
| Containers | Docker Engine (official repo), kubectl, helm, k9s, kubectx, kustomize, minikube |
| Cloud / IaC | Terraform, Packer, AWS CLI v2, Google Cloud SDK, Azure CLI, Ansible, Vagrant, GitHub CLI |
| Virtualization | KVM/QEMU, virt-manager |
| Pentest (Kali-equivalent) | **Recon:** nmap, masscan, dnsenum/recon, theharvester, recon-ng, whatweb, enum4linux, sslscan. **Web:** nikto, sqlmap, wapiti, dirb, gobuster, ffuf, feroxbuster, wfuzz, commix. **Passwords:** john, hydra, hashcat, medusa, crunch, cewl. **MITM/sniff:** wireshark, ettercap, bettercap, mitmproxy, macchanger. **Wireless:** aircrack-ng, wifite, reaver, kismet, hcxtools. **RE/forensics:** radare2, gdb, ltrace/strace, binwalk, foremost, sleuthkit, steghide, apktool, exiftool. **Pivot:** proxychains4, netcat, socat, tor, openvpn |
| Metasploit | Metasploit Framework (official Rapid7 repo) — `INSTALL_METASPLOIT` |
| Exploit dev / CTF | pwntools, GEF (gdb), ROPgadget, one_gadget, checksec, nasm — for 42 pwn/reverse projects — `INSTALL_EXPLOIT_DEV` |
| Recon (Go) | nuclei, httpx, subfinder, naabu, ffuf — `INSTALL_RECON_GO` |
| Wordlists | rockyou, SecLists, PayloadsAllTheThings in `~/wordlists` + `/usr/share/wordlists` — `INSTALL_WORDLISTS` |
| GUI security | OWASP ZAP, Ghidra (snap) — `INSTALL_BURP_ZAP` (Burp Suite is a manual download) |
| GUI apps (snap) | VS Code, PyCharm, Sublime, GitKraken, Postman, Slack, DBeaver, Insomnia, draw.io, Obsidian, VLC, GIMP, LibreOffice, KeePassXC |
| Browsers | Brave, Opera, **Google Chrome** (`.deb`), Firefox (ships with Ubuntu) |
| Everyday apps | Discord, Telegram, Signal, Thunderbird, WhatsApp, Spotify, OBS Studio, Blender, Inkscape, Krita, Audacity, Joplin, Bitwarden, Flameshot, Remmina, Okular, GNOME Boxes, Alacritty/Kitty — `INSTALL_DESKTOP_APPS` |
| CLI goodies | neovim, fzf, zoxide, eza, btop, httpie, ffmpeg, imagemagick, 7zip, aria2, pass — on top of ripgrep/fd/bat/jq/tmux |
| Flatpak | Flatpak + Flathub enabled for anything not on snap/apt — `INSTALL_FLATPAK` |
| Shell | Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting, Docker/QoL aliases, big history |
| Desktop | GNOME Tweaks + Extension Manager, Papirus icons, dark mode, dev fonts, dock/window/keyboard tweaks, battery %, Super+E → Home |
| Hardening *(opt-in)* | ClamAV, GDM user-list hidden — `INSTALL_HARDENING=1` |

## Configuration

Everything is modular. Toggle sections with environment variables, e.g.:

```sh
# Skip security tools, run headless (no GUI), keep a light GNOME theme
INSTALL_SECURITY=0 HEADLESS=1 GTK_COLOR_SCHEME=light ./setup.sh
```

Common toggles (all default to `1` / on unless noted):

```
HEADLESS=0              # 1 = skip all GUI apps + GNOME tweaks
INSTALL_IDES            INSTALL_BROWSERS        INSTALL_DB_GUI
INSTALL_K8S             INSTALL_MINIKUBE        INSTALL_DEVOPS
INSTALL_NODE            INSTALL_CONDA           INSTALL_42AI_ENV
INSTALL_RUST            INSTALL_GO              INSTALL_JAVA
INSTALL_TERRAFORM       INSTALL_AWS/GCLOUD/AZURE
INSTALL_SECURITY        INSTALL_GNOME_TWEAKS    GTK_COLOR_SCHEME=dark|light
INSTALL_UFW=0           INSTALL_HARDENING=0     INSTALL_ANDROID=0
CONDA_PY_VERSION=3.11

# Pentest lab (all default on):
INSTALL_METASPLOIT      INSTALL_EXPLOIT_DEV     INSTALL_WORDLISTS
INSTALL_RECON_GO        INSTALL_BURP_ZAP
```

Pure pentest box, no desktop bloat:

```sh
HEADLESS=1 INSTALL_IDES=0 INSTALL_K8S=0 INSTALL_CONDA=0 ./setup.sh
```

> **Authorized use only.** These tools are for your own pentest lab, 42/1337
> coursework, and CTFs. Only test systems you own or are explicitly permitted to.

### Saving & replaying your desktop look

Before applying GNOME tweaks the script snapshots your current settings to
`~/gnome-settings-backup-<timestamp>.dconf`. To replay a saved look on another
machine (and skip the preset tweaks):

```sh
GNOME_RESTORE_FROM=~/gnome-settings-backup-20260101-120000.dconf ./setup.sh
# or, standalone:   dconf load / < that-file.dconf
```

## After install

- Log out/in (or reboot) so the `docker` group, the default shell change to
  zsh, and the GNOME look fully take effect.
- Open a new shell to load `conda`, `nvm`, and the new Zsh config.
- Your `~/.zshrc` is updated in place (a timestamped backup is kept if one existed).

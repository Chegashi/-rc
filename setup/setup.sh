sudo apt-get update ; sudo full-upgrade -y; sudo apt-get dist-upgrade -y
sudo apt --fix-missing update
sudo apt-get update ; sudo full-upgrade -y; sudo apt-get dist-upgrade -y
sudo apt install snapd
sudo snap install snap-store
sudo snap install code --classic
sudo snap install gimp
sudo snap install slack
sudo snap install hugo
sudo snap install postman
sudo snap install pycharm-professional --classic
sudo snap install gitkraken --classic
sudo snap install kubectl --classic
sudo snap install sublime-text --classic
sudo snap install pycharm-community --classic
sudo snap install brave
sudo snap install opera
sudo snap install mysql-shell
sudo snap install vlc
sudo snap install termius-app
sudo snap install bcc
sudo snap install gnome-system-monitor
sudo snap install snap-store-proxy
sudo snap install gnome-clocks
sudo snap install gutenprint-printer-app
sudo snap install easy-disk-cleaner
sudo snap install bw
sudo snap install htop
sudo snap install fkill
sudo snap install tio --classic
sudo snap install libreoffice
sudo snap install emacs --classic
sudo snap install keepassxc
sudo snap install nmap
sudo snap install notepad-plus-plus
sudo snap install brave
sudo snap install gutenprint-printer-app
sudo snap install doctl
sudo snap install docker
sudo apt-get install zsh curl synaptic git vim gnome-tweaks -y
sudo addgroup --system docker
sudo adduser $USER docker
newgrp docker
sudo snap disable docker
sudo snap enable docker
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
sudo apt --fix-missing update

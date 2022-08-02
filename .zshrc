
export ZSH="/Users/mochegri/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(git)
plugins=( zsh-autosuggestions zsh-syntax-highlighting)
# git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
# git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
source $ZSH/oh-my-zsh.sh

alias code='/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code'

export PATH=$HOME/.brew/bin:$PATH
export PATH="$HOME/.brew/bin:$PATH"
export PATH=$HOME/.brew/bin:$PATH

alias dockerstp='docker stop $(docker ps -aq)'
alias dockermc='docker rm -f $(docker ps -aq)'
alias dockermi='docker rmi -f $(docker images -aq)'
alias dockermvlm='docker volume rm $(docker volume ls -q)'
alias dockermnet='docker network rm  $(docker network ls -q)'
alias dockercl='dockerstp ; dockermc ; dockermi ; dockermvlm ; dockermnet'
alias clean="rm -rf ~/Library/.42_cache_bak_; rm -rf ~/.42_cache_bak_; brew cleanup"
alias brew_install="rm -rf $HOME/.brew && git clone --depth=1 https://github.com/Homebrew/brew $HOME/.brew && echo 'export PATH=$HOME/.brew/bin:$PATH' >> $HOME/.zshrc && source $HOME/.zshrc && brew update; curl https://brew.42.fr/ | bash"
alias valgrind='brew install --HEAD https://raw.githubusercontent.com/LouisBrunner/valgrind-macos/master/valgrind.rb; brew update && brew install valgrind && alias valgrind="~/.brew/bin/valgrind"'


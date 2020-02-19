#
# Some other things you'll want:
# git-extras, vim, fonts-noto-color-emoji, nmap, htop, bwm-ng, zerotier
#
ZSH_THEME="blinks"
ZSH_THEME="powerlevel10k/powerlevel10k"
export PATH=$PATH:/usr/local/go/bin

# Download and install the latest Go version
install_go() {
  if [ ! -d /usr/local/go ] && sudo -n /bin/true; then
    gover=$(curl -s https://golang.org/VERSION\?m=text)
    goarch=amd64
    arch | grep -q arm && goarch=armv6l
    echo "Installing latest version of Go ($gover) for $goarch..."
    rm -rf /tmp/go
    mkdir -p /tmp/go
    cd /tmp/go
    wget -q "https://dl.google.com/go/$gover.linux-$goarch.tar.gz"
    sudo tar -C /usr/local -xzf go*.tar.gz
    cd; rm -rf /tmp/go
  fi
}

install_go || {
  echo "Installing Go failed!" >&2
}

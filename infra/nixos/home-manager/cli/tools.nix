{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # compression
    unzip
    gnutar
    # shell
    eza # A modern replacement for 'ls'
    fzf # A command-line fuzzy finder
    # network
    mtr # A network diagnostic tool
    iperf3
    dnsutils # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc # it is a calculator for the IPv4/v6 addresses
    # misc
    file
    which
    tree
    gnused
    gawk
    zstd
    jq
    yq-go
    glow # markdown previewer in terminal
    # security
    gnupg
    vault
    sops
    age
    #system
    htop
    btop # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring
    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files
    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb
    # git
    tig
    ydiff
  ];
}

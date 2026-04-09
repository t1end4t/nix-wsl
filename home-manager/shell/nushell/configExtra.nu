# -----------------------------------------------------
# ADD MORE CONFIG
# -----------------------------------------------------
# atuin
$env.config = {
    show_banner: false
    keybindings: []
}
source ~/.local/share/atuin/init.nu

# add to PATH
$env.PATH = (
  $env.PATH
  | split row (char esep)
  | append [~/.npm-global/bin ~/.local/bin ~/.bun/bin]
  | uniq
)

# zoxide
source ~/.zoxide.nu

# -----------------------------------------------------
# ALIASES
# -----------------------------------------------------

alias ze = zeditor $env.PWD
def h [file?: string] {
    if $file == null {
        hx $env.PWD
    } else {
        hx $file
    }
}
def l [] {ls | sort-by type}
alias c = clear
alias e = exit
alias y = yazi
alias g = lazygit
alias tp = trash-put
alias bt = bluetuith
def ld [level: int = 2] {
    eza -DR --tree --level=($level | into string)
}
alias wifi = nmtui
alias about = neofetch

# -----------------------------------------------------
# GIT
# -----------------------------------------------------

alias gs = git status
alias ga = git add
alias gc = git clone --recurse-submodules
alias gcm = git commit -m
alias gp = git push
alias gpl = git pull
alias gst = git stash
alias gcheck = git checkout

# custom prompt
$env.PROMPT_COMMAND = {||
    let dir = (pwd)
    let home = $nu.home-path
    let shown = ($dir | str replace $home "~")
    (ansi cyan_bold) + $shown + (ansi reset)
}

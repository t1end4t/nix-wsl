{
  pkgs,
  ...
}:
let
  ROOT = builtins.toString ./.;
in
{
  home.packages = with pkgs; [
    ############ aider ############
    # unstable.aider-chat-with-playwright

    ############ claude-code ############
    # curl -fsSL https://claude.ai/install.sh | bash
    # npm install -g @anthropic-ai/sandbox-runtime

    ############ codex ############
    # npm set prefix ~/.npm-global
    # npm i -g @anthropic-ai/claude-code
    # npm i -g @openai/codex
    nodejs

    # bun add -g opencode-ai
    bun

    # uvx --from git+https://github.com/oraios/serena serena
    python313
    uv

    # for sandbox
    bubblewrap
    socat
  ];

  # remember login
  services.gnome-keyring.enable = true;
}

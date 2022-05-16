#!/bin/bash
#
# Automatically scp files to https://lists.sh
# when $HOME/Lists files are changed.
#
# Setup a lists.sh account first (See https://lists.sh)
#
# Usage:
#
#   * Setup a lists.sh account first (See https://lists.sh)
#   * Update the LISTS_PATH variable if you don't want your lists to live in ~/Lists
#   * Run this script
#
set -e

### CONFIGURATION ###

LISTS_PATH="$HOME/Lists"  # Directory holding .txt files

#####################

SDPATH="$HOME/.config/systemd/user"

mkdir "$SDPATH" "$LISTS_PATH" -p

cat > "$SDPATH/lists-sh.path" <<EOF
[Unit]
Description=lists.sh directory

[Path] 
PathChanged=%h/Lists
Unit=lists-sh.service

[Install]
WantedBy=default.target
EOF

cat > "$SDPATH/lists-sh.service" <<EOF
[UNIT]
Description=Update lists.sh

[Service]  
Type=simple  
ExecStart=%h/.config/systemd/user/lists-sh.script
EOF

cat > "$SDPATH/lists-sh.script" <<EOF
#!/bin/sh
scp ~/Lists/*txt lists.sh:
EOF
chmod +x "$SDPATH/lists-sh.script"

systemctl --user daemon-reload
systemctl --user enable lists-sh.path

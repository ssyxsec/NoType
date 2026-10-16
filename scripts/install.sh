#!/bin/zsh
set -euo pipefail
notype_root="${0:A:h:h}"
notype_app="/Applications/NoType.app"
"$notype_root/scripts/build.sh"
if pgrep -x NoType >/dev/null; then
  print -u2 '请先退出 NoType，再运行安装脚本。'
  exit 1
fi
ditto "$notype_root/dist/NoType.app" "$notype_app"
codesign --verify --deep --strict "$notype_app"
notype_legacy="$HOME/Applications/NoType.app"
if [[ -d "$notype_legacy" ]]; then
  mkdir -p "$HOME/.Trash"
  mv "$notype_legacy" "$HOME/.Trash/NoType-legacy-$(date +%Y%m%d-%H%M%S).app"
fi
open "$notype_app"
print "已安装：$notype_app"

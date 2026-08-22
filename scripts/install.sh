#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
check_only=false

case ${1:-} in
  '') ;;
  --check) check_only=true ;;
  -h|--help)
    print "Usage : ${0:t} [--check]"
    print 'Installe avec Homebrew les outils requis, puis Pagefind avec npm.'
    exit 0
    ;;
  *) print -u2 "Usage : ${0:t} [--check]"; exit 64 ;;
esac

typeset -A formula_for
formula_for=(
  gum gum
  fzf fzf
  jq jq
  hugo hugo
  node node
  npm node
  npx node
)
typeset -a tools missing_system
typeset -aU missing_formulae
tools=(gum fzf jq hugo node npm npx)

for tool in $tools; do
  [[ -n ${commands[$tool]:-} ]] || missing_formulae+=("$formula_for[$tool]")
done

if (( ${#missing_formulae} > 0 )); then
  print -r -- "Outils Homebrew manquants : ${(j:, :)missing_formulae}"
  if $check_only; then
    exit 1
  fi
  brew_bin=${commands[brew]:-}
  [[ -n $brew_bin ]] || {
    print -u2 'Homebrew est introuvable : https://brew.sh'
    exit 1
  }
  "$brew_bin" install --formula "${missing_formulae[@]}"
  rehash
else
  print 'Outils Homebrew : OK'
fi

for tool in /bin/zsh /usr/bin/curl /usr/bin/perl /usr/bin/open /usr/bin/osascript /usr/bin/sips; do
  [[ -x $tool ]] || missing_system+=("$tool")
done
if (( ${#missing_system} > 0 )); then
  print -u2 -- "Outils macOS manquants : ${(j:, :)missing_system}"
  exit 1
fi
/usr/bin/perl -MXML::LibXML -e 1 2>/dev/null || {
  print -u2 'Le module système Perl XML::LibXML est absent ; le catalogue BnF ne peut pas fonctionner.'
  exit 1
}
print 'Outils macOS : OK'

if [[ ! -x "$repo_root/node_modules/.bin/pagefind" ]]; then
  if $check_only; then
    print -u2 'Pagefind est absent. Lancer scripts/install.sh pour installer les dépendances npm.'
    exit 1
  fi
  npm_bin=${commands[npm]:-}
  [[ -n $npm_bin ]] || { print -u2 'npm est introuvable après installation de Node.'; exit 1; }
  "$npm_bin" ci --prefix "$repo_root"
else
  print 'Dépendances npm : OK'
fi

print
print 'Environnement prêt.'

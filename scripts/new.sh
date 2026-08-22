#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
installer="$script_dir/install.sh"

if ! dependency_report=$("$installer" --check 2>&1); then
  print -r -- "$dependency_report"
  if [[ ! -r /dev/tty ]]; then
    print -u2 'Installation interactive impossible sans terminal.'
    exit 1
  fi

  answer=''
  read "answer?Installer maintenant les dépendances manquantes ? [o/N] " </dev/tty || true
  case ${answer:l} in
    o|oui|y|yes) "$installer" ;;
    *) print -u2 'Installation annulée.'; exit 1 ;;
  esac
  rehash
fi

source "$script_dir/lib/article.sh"
article_require_tools

typeset -a rows
for directory in "$article_repo_root"/content/*(/N); do
  section=${directory:t}
  [[ $section != pages && $section != .* ]] || continue
  indexes=("$directory"/*/index.md(N))
  [[ -f "$directory/_index.md" || ${#indexes} -gt 0 ]] || continue
  case $section in
    serie) label='Séries' ;;
    film) label='Films' ;;
    album) label='Albums' ;;
    livre) label='Livres' ;;
    jeu-video) label='Jeux vidéo' ;;
    photo) label='Photos' ;;
    spectacle) label='Spectacles' ;;
    *) label=${section//-/ } ;;
  esac
  rows+=("${#indexes}"$'\t'"$section"$'\t'"$label")
done
(( ${#rows} > 0 )) || article_die 'Aucune section Hugo publiable trouvée.'

selected=$(print -rl -- $rows | /usr/bin/sort -rn -k1,1 | /usr/bin/awk -F '\t' '{ print $2 "\t" $3 }' | "$article_fzf_bin" --delimiter $'\t' --with-nth 2 --header 'Quelle catégorie ?' --prompt 'Filtrer > ' --height 15 --layout reverse --border --no-sort) || exit 0
[[ -n $selected ]] || exit 0
section=${selected%%$'\t'*}

case $section in
  # Le menu fzf lit sa liste depuis un pipe. Les assistants doivent ensuite
  # reprendre le vrai terminal pour que Gum puisse recevoir le clavier.
  serie) exec "$script_dir/categories/serie.sh" </dev/tty ;;
  film|livre|jeu-video|album|photo) exec "$script_dir/categories/$section.sh" </dev/tty ;;
  *) exec "$script_dir/categories/default.sh" "$section" </dev/tty ;;
esac

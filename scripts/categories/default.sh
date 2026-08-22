#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
source "$lib_dir/article.sh"
article_require_tools
section=${1:-}
[[ -n $section ]] || article_die "Usage: ${0:t} SECTION"
title=$("$article_gum_bin" input --header 'Quel titre ?' --width 80) || article_cancel
[[ -n $title ]] || article_die 'Le titre est obligatoire.'
slug=$(article_slug "$(print -rn -- "$title" | "$lib_dir/slugify.pl" propose)") || article_cancel
file=$(article_create "$section" "$slug" "$title")
article_open "$file"

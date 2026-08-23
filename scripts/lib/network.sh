#!/bin/zsh

# Conserve les diagnostics des tentatives intermédiaires de curl et ne les
# affiche que si la commande échoue finalement après ses éventuelles relances.
network_curl() {
  local error_file exit_code
  error_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-curl.XXXXXX") || return 1

  if /usr/bin/curl "$@" 2>"$error_file"; then
    exit_code=0
  else
    exit_code=$?
    /bin/cat "$error_file" >&2
  fi
  /bin/rm -f -- "$error_file"
  return "$exit_code"
}

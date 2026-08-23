#!/bin/zsh

people_name() {
  print -r -- "$1" | /usr/bin/perl -CS -Mutf8 -pe 's/ (?=[^ ]+\z)/\x{a0}/'
}

people_join() {
  local -a values=("$@")
  local count=${#values} index result=''
  (( count > 0 )) || return 0
  (( count == 1 )) && { print -r -- "$values[1]"; return; }

  for (( index = 1; index <= count; index++ )); do
    if (( index == 1 )); then
      result=$values[index]
    elif (( index == count )); then
      result+=" et $values[index]"
    else
      result+=", $values[index]"
    fi
  done
  print -r -- "$result"
}

people_join_names() {
  local -a names
  local name
  for name in "$@"; do
    [[ -n $name ]] && names+=("$(people_name "$name")")
  done
  people_join "${names[@]}"
}

people_split_credits() {
  local value=$1
  if [[ $value == *' & '* ]]; then
    print -r -- "$value" | /usr/bin/perl -CS -Mutf8 -pe 's/\s*(?:,|&)\s*/\n/g'
  else
    print -r -- "$value"
  fi
}

people_westernize_tmdb() {
  local localized=$1 western=$2
  jq -cn --argjson localized "$localized" --argjson western "$western" '
    def western_name:
      test("\\p{Latin}")
      and (test("[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Cyrillic}\\p{Arabic}]") | not);
    ([ $western
       | .. | objects
       | select(has("id") and has("name") and has("original_name"))
       | select(.name | western_name)
       | {key: (.id | tostring), value: .name} ]
     | from_entries) as $names
    | $localized
    | walk(
        if type == "object" and has("id") and has("name") and has("original_name")
           and ($names[.id | tostring] // "") != ""
        then .name = $names[.id | tostring]
        else .
        end
      )'
}

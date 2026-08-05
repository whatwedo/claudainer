#!/usr/bin/env bash
# Shared helper functions for claudainer, sourced by source.sh.

# _claudainer_yaml_list <file> <key>
# Print each item of the YAML block sequence under <key> in <file>, one per
# line. Supports the small subset claudainer needs: a top-level "<key>:" line
# followed by "- value" items (at any indentation), inline "#" comments, blank
# lines, and single- or double-quoted values. Scanning stops at the next
# top-level key. No-op if the file is missing or unreadable.
_claudainer_yaml_list() {
  local file="$1" key="$2"
  [ -f "$file" ] && [ -r "$file" ] || return 0

  local line in_list=false trimmed val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                       # drop inline comments
    line="${line%"${line##*[![:space:]]}"}"  # trim trailing whitespace
    [ -z "$line" ] && continue               # blank line
    case "$line" in
      "$key":*) in_list=true; continue ;;
    esac
    [ "$in_list" = true ] || continue
    trimmed="${line#"${line%%[![:space:]]*}"}"  # strip leading whitespace
    case "$trimmed" in
      -*)
        val="${trimmed#-}"
        val="${val#"${val%%[![:space:]]*}"}" # trim whitespace after the dash
        case "$val" in
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
          \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
        [ -n "$val" ] && printf '%s\n' "$val"
        ;;
      *) in_list=false ;;                     # not a list item; block ended
    esac
  done < "$file"
}

# _claudainer_yaml_scalar <file> <key>
# Print the value of a top-level "<key>: value" line in <file> (inline "#"
# comments stripped, single/double quotes unwrapped). Prints nothing if the
# key is absent, its value is blank, or the file is missing/unreadable. Only
# matches column-0 "<key>:" lines, not list items or other nested content.
_claudainer_yaml_scalar() {
  local file="$1" key="$2"
  [ -f "$file" ] && [ -r "$file" ] || return 0

  local line val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                       # drop inline comments
    line="${line%"${line##*[![:space:]]}"}"  # trim trailing whitespace
    case "$line" in
      "$key":*)
        val="${line#"$key":}"
        val="${val#"${val%%[![:space:]]*}"}" # trim leading whitespace
        case "$val" in
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
          \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
        [ -n "$val" ] && printf '%s\n' "$val"
        return 0
        ;;
    esac
  done < "$file"
}

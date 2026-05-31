# ============================================================
# palace.zsh — zsh helpers for the palace notes repo
# ============================================================
# Sourced by ~/.dotfiles/zsh/aliases.zsh when this file is readable.
# Lives in the palace wrapper repo so the aliases ship with palace
# itself and stay in sync. PALACE_DIR is exported by the caller.

# Guard for palace functions. Checks in stages so error messages point at
# the real problem (wrapper dir missing vs palace missing vs not yet decrypted).
_palace_check() {
   local parent="${PALACE_DIR%/*}"
   if [ ! -d "$parent" ]; then
      echo "palace: parent '$parent' does not exist, clone it" >&2
      return 1
   fi
   if [ ! -d "$PALACE_DIR" ]; then
      echo "palace: '$PALACE_DIR' does not exist (palace itself missing, decrypt it)" >&2
      return 1
   fi
   if [ ! -d "$PALACE_DIR/notes" ]; then
      echo "palace: '$PALACE_DIR' is decrypted — no 'notes/' inside" >&2
      return 1
   fi
}

# Create-or-open $PALACE_DIR/<subdir>/<filename> with a date + [[tag]] header,
# then cd into palace and open in $EDITOR. Used by daily/weekly/shot/tg-create.
_palace_note() {
   local subdir="$1" filename="$2" tag="$3"
   _palace_check || return 1
   local note_dir="$PALACE_DIR/$subdir"
   mkdir -p "$note_dir"
   local note="$note_dir/$filename"
   if [ ! -s "$note" ]; then
      cat > "$note" <<EOF
$(date +'%a %d %b %Y at %H:%M:%S')

[[$tag]]
EOF
   fi
   ( cd "$PALACE_DIR" && ${EDITOR:-nvim} "$note" )
}

# Today's daily note: notes/management/daily/YYYY/MM/YYYY-MM-DD.md
daily()  { _palace_note "notes/management/daily/$(date +'%Y/%m')" "$(date +'%Y-%m-%d').md"       daily;  }

# This ISO week's note: notes/management/weekly/YYYY-Www.md
weekly() { _palace_note "notes/management/weekly"                  "$(date +'%G-W%V').md"          weekly; }

# Timestamped daily shot: notes/management/daily/YYYY/MM/YYYY-MM-DDTHH.MM.md
shot()   { _palace_note "notes/management/daily/$(date +'%Y/%m')" "$(date +'%Y-%m-%dT%H.%M').md" shots;  }

# dn [-n|-l FILE|-L]   manage do-notes under notes/management/do/
#   (no args)  open the last do-note
#   -n         create new do-note for current ISO week, mark as last
#   -l FILE    mark FILE (basename) as last (flip the flag)
#   -L         list do-notes (last marked with *)
#
# "Last" pointer lives at $PALACE_DIR/.last-do (basename only).
# Filenames stay stable: do-YYYY-WW.md (ISO year + ISO week).
dn() {
   _palace_check || return 1
   local subdir="notes/management/do"
   local note_dir="$PALACE_DIR/$subdir"
   local last_file="$PALACE_DIR/.last-do"
   mkdir -p "$note_dir"

   case "$1" in
      -n|--new)
         local yr=$(date +%G) wk=$(date +%V)
         local name="do-${yr}-W${wk}.md"
         printf "%s\n" "$name" > "$last_file"
         _palace_note "$subdir" "$name" do
         ;;
      -l|--last)
         local target="$2"
         if [ -z "$target" ]; then
            echo "dn: -l requires a filename (basename)" >&2
            return 1
         fi
         if [ ! -f "$note_dir/$target" ]; then
            echo "dn: no such note: $note_dir/$target" >&2
            return 1
         fi
         printf "%s\n" "$target" > "$last_file"
         echo "Marked as last: $target"
         ;;
      -L|--list)
         local last=""
         [ -f "$last_file" ] && last=$(cat "$last_file")
         find "$note_dir" -maxdepth 1 -type f -name '*.md' \
               2>/dev/null | LC_ALL=C sort \
            | while IFS= read -r f; do
                  local b="${f##*/}"
                  if [ "$b" = "$last" ]; then
                     printf "  * %s\n" "$b"
                  else
                     printf "    %s\n" "$b"
                  fi
              done
         ;;
      "")
         if [ ! -f "$last_file" ]; then
            echo "dn: no last note recorded. Run 'dn -n' first." >&2
            return 1
         fi
         local last_name=$(cat "$last_file")
         local target="$note_dir/$last_name"
         if [ ! -f "$target" ]; then
            echo "dn: stale pointer (no file at $target)" >&2
            return 1
         fi
         ( cd "$PALACE_DIR" && ${EDITOR:-nvim} "$target" )
         ;;
      *)
         echo "usage: dn [-n|-l FILE|-L]" >&2
         return 1
         ;;
   esac
}

# tg [-l|-n]   manage murmur notes under notes/me/writing/murmur/
#   -l         fzf-pick an existing note (by recency) and open it
#   -n         create a new note (default; prompts for a name)
tg() {
   _palace_check || return 1
   local subdir="notes/me/writing/murmur"
   local note_dir="$PALACE_DIR/$subdir"
   mkdir -p "$note_dir"

   case "$1" in
      -l)
         if command -v fzf > /dev/null 2>&1; then
            local pick
            pick=$(ls -1t "$note_dir" 2>/dev/null | fzf --prompt='murmur > ' --no-sort) || return 1
            [ -z "$pick" ] && return 1
            ( cd "$PALACE_DIR" && ${EDITOR:-nvim} "$note_dir/$pick" )
         else
            ls -1t "$note_dir"
         fi
         ;;
      -n|"")
         local name
         read "name?murmur note name: "
         [ -z "$name" ] && { echo "tg: empty name" >&2; return 1; }
         [[ "$name" != *.md ]] && name="${name}.md"
         _palace_note "$subdir" "$name" murmur
         ;;
      *)
         echo "usage: tg [-l|-n]" >&2
         return 1
         ;;
   esac
}

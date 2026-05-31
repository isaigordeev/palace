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

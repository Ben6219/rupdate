#!/usr/bin/env bash
# rupdate.sh — hotfix: blocs case simplifiés, compatible bash, sans pièges
set -euo pipefail

resolve_libs="/opt/resolve/libs"
DRY_RUN=0
ASSUME_YES=0
NO_LDCONFIG=0
FAST=0
PURGE_BAK=""
PURGE_DAYS_DEFAULT=90

usage() {
  cat <<EOF
Usage: sudo ./rupdate.sh [--check] [--yes] [--no-ldconfig] [--fast] [--purge-bak [JOURS]]
  --check            Lecture seule (dry-run)
  --yes              Répond 'oui' automatiquement aux confirmations
  --no-ldconfig      N'utilise pas ldconfig -p
  --fast             Utilise uniquement ldconfig -p (plus rapide)
  --purge-bak [N]    Supprime *.bak.* de plus de N jours (défaut 90) puis quitte
EOF
}

confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  read -r -p "$1 (o/N) : " _a
  [ "${_a:-}" = "o" ] || [ "${_a:-}" = "O" ]
}

# ---------- Parse options (case simple, sans imbrication) ----------
while [ $# -gt 0 ]; do
  opt="$1"
  case "$opt" in
    --check)        DRY_RUN=1; shift ;;
    --yes)          ASSUME_YES=1; shift ;;
    --no-ldconfig)  NO_LDCONFIG=1; shift ;;
    --fast)         FAST=1; NO_LDCONFIG=0; shift ;;
    --purge-bak)
      shift
      if [ $# -gt 0 ] && printf '%s' "$1" | grep -Eq '^[0-9]+$'; then
        PURGE_BAK="$1"; shift
      else
        PURGE_BAK="$PURGE_DAYS_DEFAULT"
      fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $opt"; usage; exit 2 ;;
  esac
done

# ---------- Détection famille distro (sans =~, via case insensible) ----------
detect_family() {
  local id like
  id=""; like=""
  if [ -r /etc/os-release ]; then . /etc/os-release; fi
  id=$(printf '%s' "${ID:-}" | tr '[:upper:]' '[:lower:]')
  like=$(printf '%s' "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')

  case "$id,$like" in
    *opensuse*|*sles*|*,*suse*)                echo "suse" ;;
    *fedora*|*rhel*|*rocky*|*alma*|*centos*|*,*rhel*|*,*fedora*|*,*centos*) echo "rhel" ;;
    *debian*|*ubuntu*|*linuxmint*|*pop*|*zorin*|*kali*|*parrot*|*,*debian*|*,*ubuntu*) echo "debian" ;;
    *arch*|*manjaro*|*garuda*|*endeavouros*)   echo "arch" ;;
    *gentoo*|*calculate*)                      echo "gentoo" ;;
    *)                                         echo "generic" ;;
  esac
}

family="$(detect_family)"

# ---------- Chemins système par famille (case simple) ----------
system_dirs=()
case "$family" in
  suse|rhel|gentoo|arch)
    system_dirs=(/lib64 /usr/lib64 /lib /usr/lib)
    ;;
  debian)
    system_dirs=(/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib64 /lib /usr/lib)
    ;;
  *)
    system_dirs=(/lib64 /usr/lib64 /lib /usr/lib /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu)
    ;;
esac

bases=( "libgio-2.0.so.0" "libglib-2.0.so.0" "libgmodule-2.0.so.0" "libgobject-2.0.so.0" )

get_version() {
  # extrait après base: libglib-2.0.so.0.8600.1 -> 8600.1
  local p="$1" base="$2" b
  b="$(basename "$p")"
  printf "%s" "${b#${base}.}"
}

ver_lt() {
  local a="$1" b="$2" first
  first="$(printf "%s\n%s\n" "$a" "$b" | LC_ALL=C sort -V | head -n1)"
  [ "$first" = "$a" ] && [ "$a" != "$b" ]
}

find_best_in_dir() {
  local dir="$1" base="$2" exact resolved f
  [ -d "$dir" ] || return 1
  set +u
  shopt -s nullglob
  local candidates=()
  exact="$dir/$base"
  if [ -e "$exact" ]; then
    resolved="$(readlink -f "$exact" 2>/dev/null || true)"
    if [ -n "$resolved" ] && [ -e "$resolved" ]; then candidates+=("$resolved"); fi
  fi
  for f in "$dir/$base".*; do
    [ -f "$f" ] && candidates+=("$f")
  done
  shopt -u nullglob
  set -u
  [ ${#candidates[@]} -gt 0 ] || return 1
  # choisir la version max
  local lines=() v c
  for c in "${candidates[@]}"; do
    v="$(get_version "$c" "$base")"
    lines+=("$v"$'\t'"$c")
  done
  printf "%s\n" "${lines[@]}" | LC_ALL=C sort -V -k1,1 | tail -n1 | cut -f2-
}

ldconfig_list() {
  [ "$NO_LDCONFIG" -eq 0 ] || return 1
  command -v ldconfig >/dev/null 2>&1 || return 1
  ldconfig -p 2>/dev/null || return 1
}

find_best_in_system() {
  local base="$1" best="" out paths c v
  if [ "$FAST" -eq 1 ]; then
    out="$(ldconfig_list || true)"
    if [ -n "${out:-}" ]; then
      paths="$(printf "%s\n" "$out" | grep -E "^[[:space:]]*${base}[[:space:]]" | sed 's@^.*=>[[:space:]]*@@')"
      if [ -n "$paths" ]; then
        local lines=()
        while IFS= read -r c; do
          [ -n "$c" ] && [ -e "$c" ] || continue
          v="$(get_version "$c" "$base")"
          lines+=("$v"$'\t'"$c")
        done <<< "$paths"
        if [ ${#lines[@]} -gt 0 ]; then
          best="$(printf "%s\n" "${lines[@]}" | LC_ALL=C sort -V -k1,1 | tail -n1 | cut -f2-)"
        fi
      fi
    fi
    [ -n "$best" ] || return 1
    printf "%s\n" "$best"
    return 0
  fi

  out="$(ldconfig_list || true)"
  if [ -n "${out:-}" ]; then
    paths="$(printf "%s\n" "$out" | grep -E "^[[:space:]]*${base}[[:space:]]" | sed 's@^.*=>[[:space:]]*@@')"
    if [ -n "$paths" ]; then
      local lines=()
      while IFS= read -r c; do
        [ -n "$c" ] && [ -e "$c" ] || continue
        v="$(get_version "$c" "$base")"
        lines+=("$v"$'\t'"$c")
      done <<< "$paths"
      if [ ${#lines[@]} -gt 0 ]; then
        best="$(printf "%s\n" "${lines[@]}" | LC_ALL=C sort -V -k1,1 | tail -n1 | cut -f2-)"
      fi
    fi
  fi

  if [ -z "$best" ]; then
    local p d
    for d in "${system_dirs[@]}"; do
      p="$(find_best_in_dir "$d" "$base" 2>/dev/null || true)" || true
      [ -z "$p" ] && continue
      if [ -z "$best" ]; then
        best="$p"
      else
        if ver_lt "$(get_version "$best" "$base")" "$(get_version "$p" "$base")"; then
          best="$p"
        fi
      fi
    done
  fi

  [ -n "$best" ] || return 1
  printf "%s\n" "$best"
}

ensure_root() {
  if [ "$EUID" -ne 0 ]; then echo "Lance en root (sudo) pour écrire dans ${resolve_libs}."; exit 1; fi
}

safe_install() {
  local src="$1" dst="$2"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] install -m 0644 \"$src\" \"$dst\""
  else
    install -m 0644 "$src" "$dst"
  fi
}

backup_file() {
  local p="$1" ts="$2"
  [ -e "$p" ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] cp -a \"$p\" \"${p}.bak.$ts\""
  else
    cp -a "$p" "${p}.bak.$ts"
  fi
}

purge_bak() {
  local days="$1"
  [ -d "$resolve_libs" ] || { echo "Dossier introuvable: $resolve_libs"; exit 1; }
  echo "Purge des backups (*.bak.*) > ${days} jours dans ${resolve_libs}:"
  mapfile -t candidates < <(find "$resolve_libs" -type f -name "*.bak.*" -mtime +"$days" -print 2>/dev/null || true)
  if [ ${#candidates[@]} -eq 0 ]; then echo "Aucun backup à purger."; exit 0; fi
  for f in "${candidates[@]}"; do echo "  - $f"; done
  if confirm "Confirmer la suppression de ${#candidates[@]} fichier(s)"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] Suppression ignorée."
    else
      for f in "${candidates[@]}"; do echo "rm -f \"$f\""; rm -f "$f"; done
      echo "Purge terminée."
    fi
  else
    echo "Purge annulée."
  fi
  exit 0
}

# ---- Mode purge puis sortie
if [ -n "$PURGE_BAK" ]; then purge_bak "$PURGE_BAK"; fi

# ---- Préconditions
ensure_root
[ -d "$resolve_libs" ] || { echo "Dossier introuvable: $resolve_libs"; exit 1; }

echo "Distro: $family"
echo "Mode : $([ "$DRY_RUN" -eq 1 ] && printf "dry-run ")$([ "$FAST" -eq 1 ] && printf "fast ")$([ "$NO_LDCONFIG" -eq 1 ] && printf "no-ldconfig ")"
echo "Dirs : ${system_dirs[*]}"
echo ""

missing=(); outdated=()
declare -A rep_res rep_sys sys_file res_file

echo "Évaluation des bibliothèques..."
for base in "${bases[@]}"; do
  res_best="$(find_best_in_dir "$resolve_libs" "$base" 2>/dev/null || true)" || true
  sys_best="$(find_best_in_system "$base" 2>/dev/null || true)" || true
  if [ -z "${sys_best:-}" ]; then
    echo "  $base : aucune version trouvée côté système."
    continue
  fi
  sys_ver="$(get_version "$sys_best" "$base")"; rep_sys["$base"]="$sys_ver"; sys_file["$base"]="$sys_best"
  if [ -z "${res_best:-}" ]; then
    echo "  $base : manquant dans $resolve_libs (système: $sys_ver)"
    missing+=("$base")
    continue
  fi
  res_ver="$(get_version "$res_best" "$base")"; rep_res["$base"]="$res_ver"; res_file["$base"]="$res_best"
  printf "  %-22s resolve: %-12s système: %-12s\n" "$base" "$res_ver" "$sys_ver"
  if ver_lt "$res_ver" "$sys_ver"; then outdated+=("$base"); fi
done

echo ""
echo "===== RÉSUMÉ ====="
if [ ${#missing[@]} -gt 0 ]; then
  echo "Manquants :"; for b in "${missing[@]}"; do echo "  - $b (système: ${rep_sys[$b]})"; done
else echo "Aucun fichier manquant."; fi
if [ ${#outdated[@]} -gt 0 ]; then
  echo "Plus anciens dans /opt/resolve/libs :"; for b in "${outdated[@]}"; do echo "  - $b (resolve: ${rep_res[$b]} < système: ${rep_sys[$b]})"; done
else echo "Aucune version plus ancienne détectée."; fi
echo "=================="
echo ""

# ---- Copie des manquants
if [ ${#missing[@]} -gt 0 ]; then
  if confirm "Copier les fichiers manquants depuis le système vers $resolve_libs ?"; then
    echo "Validation finale:"; for b in "${missing[@]}"; do echo "  - $b -> $(basename "${sys_file[$b]}")"; done
    if confirm "Confirmer la copie"; then
      for b in "${missing[@]}"; do
        src="${sys_file[$b]}"; dst="$resolve_libs/$(basename "$src")"
        echo "Copie $src -> $dst"; safe_install "$src" "$dst"
      done
      echo "Copie terminée."
    else echo "Copie annulée."; fi
  else echo "Copie refusée."; fi
fi

# ---- Remplacement des plus anciennes
if [ ${#outdated[@]} -gt 0 ]; then
  if confirm "Remplacer les bibliothèques plus anciennes par les versions système plus récentes ?"; then
    echo "Validation finale:"; for b in "${outdated[@]}"; do echo "  - $b : ${rep_res[$b]} -> ${rep_sys[$b]}"; done
    if confirm "Confirmer le remplacement"; then
      ts="$(date +%Y%m%d-%H%M%S)"
      for b in "${outdated[@]}"; do
        src="${sys_file[$b]}"; dst="$resolve_libs/$(basename "$src")"
        if [ -n "${res_file[$b]:-}" ] && [ -e "${res_file[$b]}" ]; then
          echo "Sauvegarde: ${res_file[$b]} -> ${res_file[$b]}.bak.$ts"; backup_file "${res_file[$b]}" "$ts"
        fi
        echo "Remplacement: $src -> $dst"; safe_install "$src" "$dst"
      done
      if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled && command -v restorecon >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] restorecon -R \"$resolve_libs\""; else restorecon -R "$resolve_libs" || true; fi
      fi
      echo "Remplacement terminé."
    else echo "Remplacement annulé."; fi
  else echo "Remplacement refusé."; fi
fi

echo ""
echo "Fini. Relance Resolve si nécessaire."

#!/usr/bin/env bash
# rupdate.sh — v1.3.1
# - Menu interactif en boucle (avec affichage garanti)
# - Auto-détection des .run (., $PWD, ~/Téléchargements, ~/Downloads)
# - Actions rootées seulement au moment d'agir (pas au démarrage)
# - --debug pour tracer les étapes
# - ShellCheck clean

set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8

SCRIPT_VERSION="1.3.1"
resolve_libs="/opt/resolve/libs"

# Flags
DRY_RUN=0
ASSUME_YES=0
NO_LDCONFIG=0
FAST=0
QUIET=0
VERBOSE=1
DEBUG=0
PURGE_BAK=""
PURGE_DAYS_DEFAULT=90

UPGRADE_RUN=""
VERSION_ONLY=0
UNINSTALL_ONLY=0
SHOW_MENU=1

dbg(){ [ "$DEBUG" -eq 1 ] && printf "🐞 %s\n" "$*" >&2 || true; }
say(){ [ "$QUIET" -eq 0 ] && printf "%s\n" "$*"; }
info(){ [ "$QUIET" -eq 0 ] && printf "ℹ️  %s\n" "$*"; }
ok(){ [ "$QUIET" -eq 0 ] && printf "✅ %s\n" "$*"; }
warn(){ printf "⚠️  %s\n" "$*" >&2; }
err(){ printf "❌ %s\n" "$*" >&2; }
hr(){ [ "$QUIET" -eq 0 ] && printf -- "---------------------------------------------\n"; }
title(){ [ "$QUIET" -eq 0 ] && { hr; printf "🧩 %s\n" "$*"; hr; }; }
stepn=0
step(){ stepn=$((stepn+1)); [ "$QUIET" -eq 0 ] && printf "\n▶️  Étape %d: %s\n" "$stepn" "$*"; }

ask_yes_no(){
  local q="$1" a
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  printf "%s (o/N) : " "$q"
  read -r a
  [ "${a:-}" = "o" ] || [ "${a:-}" = "O" ]
}
confirm(){ ask_yes_no "$1"; }

usage(){
  cat <<'EOF'
rupdate.sh — Mainteneur compatibilité DaVinci Resolve (Linux)

USAGE:
  sudo ./rupdate.sh [OPTIONS]     # exécute selon options
  sudo ./rupdate.sh               # menu interactif (boucle)

OPTIONS GÉNÉRALES:
  --help, -h        Aide          --quiet / --verbose
  --debug           Trace interne  --yes (répond oui)  --check (lecture seule)

DÉTECTION:
  --no-ldconfig     N'utilise pas ldconfig -p
  --fast            N'utilise QUE ldconfig -p (plus rapide)

LIBS (/opt/resolve/libs):
  --purge-bak [N]   Supprime *.bak.* de plus de N jours (def=90), puis quitte

CYCLE RESOLVE:
  --version-only               Affiche version installée (+ installeur si fourni) et quitte
  --upgrade <Resolve*.run>     Compare; si plus récent: désinstalle/installe + corrige libs
  --uninstall-resolve          Lance le désinstalleur officiel, puis quitte
EOF
}

# ----- Options
parsed_any=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --quiet) QUIET=1; VERBOSE=0; parsed_any=1 ;;
    --verbose) QUIET=0; VERBOSE=1; parsed_any=1 ;;
    --debug) DEBUG=1; parsed_any=1 ;;
    --yes) ASSUME_YES=1; parsed_any=1 ;;
    --check) DRY_RUN=1; parsed_any=1 ;;
    --no-ldconfig) NO_LDCONFIG=1; parsed_any=1 ;;
    --fast) FAST=1; NO_LDCONFIG=0; parsed_any=1 ;;
    --purge-bak) parsed_any=1; shift; PURGE_BAK="${1:-$PURGE_DAYS_DEFAULT}" ;;
    --version-only) VERSION_ONLY=1; parsed_any=1 ;;
    --uninstall-resolve) UNINSTALL_ONLY=1; parsed_any=1 ;;
    --upgrade) parsed_any=1; UPGRADE_RUN="${2:-}"; [ -n "$UPGRADE_RUN" ] || { err "--upgrade requiert un .run"; exit 2; }; shift ;;
    *) err "Option inconnue: $1"; usage; exit 2 ;;
  esac
  shift || true
done
[ "$parsed_any" -eq 1 ] && SHOW_MENU=0

# ----- Distro
detect_family(){
  local id like
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi
  id=$(printf '%s' "${ID:-}" | tr '[:upper:]' '[:lower:]')
  like=$(printf '%s' "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
  if [[ "$id" == *opensuse* || "$id" == *sles* || "$like" == *suse* ]]; then echo "suse"
  elif [[ "$id" == *fedora* || "$id" == *rhel* || "$id" == *rocky* || "$id" == *alma* || "$id" == *centos* || "$like" == *rhel* || "$like" == *fedora* || "$like" == *centos* ]]; then echo "rhel"
  elif [[ "$id" == *debian* || "$id" == *ubuntu* || "$id" == *linuxmint* || "$id" == *pop* || "$id" == *zorin* || "$id" == *kali* || "$id" == *parrot* || "$like" == *debian* || "$like" == *ubuntu* ]]; then echo "debian"
  elif [[ "$id" == *arch* || "$id" == *manjaro* || "$id" == *garuda* || "$id" == *endeavouros* ]]; then echo "arch"
  elif [[ "$id" == *gentoo* || "$id" == *calculate* ]]; then echo "gentoo"
  else echo "generic"; fi
}
family="$(detect_family)"
case "$family" in
  suse|rhel|gentoo|arch) system_dirs=(/lib64 /usr/lib64 /lib /usr/lib) ;;
  debian)                system_dirs=(/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu /lib64 /usr/lib64 /lib /usr/lib) ;;
  *)                     system_dirs=(/lib64 /usr/lib64 /lib /usr/lib /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu) ;;
esac
dbg "family=$family; dirs=${system_dirs[*]}"

ensure_root(){ if [ "$EUID" -ne 0 ]; then err "Requiert sudo/root pour cette action."; exit 1; fi }

ldconfig_list(){ [ "$NO_LDCONFIG" -eq 0 ] || return 1; command -v ldconfig >/dev/null 2>&1 || return 1; ldconfig -p 2>/dev/null || return 1; }

# ----- Resolve version / install
ver_lt(){ local a="$1" b="$2" first; first="$(printf "%s\n%s\n" "$a" "$b" | LC_ALL=C sort -V | head -n1)"; [ "$first" = "$a" ] && [ "$a" != "$b" ]; }
get_installed_resolve_version(){
  if [ -r /opt/resolve/version.txt ]; then tr -d '\r' < /opt/resolve/version.txt | head -n1 | sed 's/[[:space:]]*$//'; return 0; fi
  if [ -x /opt/resolve/bin/resolve ]; then /opt/resolve/bin/resolve --version 2>/dev/null | sed -n '1s/[^0-9.]*\([0-9][0-9.]*\).*/\1/p' && return 0 || true; fi
  if command -v rpm >/dev/null 2>&1; then rpm -q --qf '%{VERSION}\n' davinci-resolve 2>/dev/null && return 0 || true; fi
  if command -v dpkg >/dev/null 2>&1; then dpkg -l | awk '/davinci-resolve/{print $3; exit}' && return 0 || true; fi
  return 1
}
parse_installer_version(){
  local p="$1" base; base="$(basename "$p")"
  printf "%s" "$base" | sed -n 's/.*Resolve[_-]\([0-9][0-9.]*\)[_-].*/\1/p' && return 0
  if command -v strings >/dev/null 2>&1; then strings "$p" 2>/dev/null | sed -n 's/.*Resolve[^0-9]*\([0-9][0-9.]*\).*/\1/p' | head -n1 && return 0 || true; fi
  return 1
}
has_resolve(){ [ -x /opt/resolve/bin/resolve ] || [ -d /opt/resolve ]; }
run_uninstaller(){ ensure_root; if [ -x "/opt/resolve/Uninstall Resolve" ]; then "/opt/resolve/Uninstall Resolve"; return 0; fi; if [ -x "/opt/resolve/uninstall.sh" ]; then "/opt/resolve/uninstall.sh"; return 0; fi; warn "Désinstalleur introuvable."; return 1; }
run_installer(){ ensure_root; local runfile="$1"; [ -f "$runfile" ] || { err "Installeur introuvable: $runfile"; return 1; }; if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] sh \"$runfile\""; else sh "$runfile"; fi }

# ----- Libs
bases=( "libgio-2.0.so.0" "libglib-2.0.so.0" "libgmodule-2.0.so.0" "libgobject-2.0.so.0" )
get_version_suffix(){ local p="$1" base="$2" b; b="$(basename "$p")"; printf "%s" "${b#"${base}".}"; }
find_best_in_dir(){
  local dir="$1" base="$2" exact resolved f
  [ -d "$dir" ] || return 1
  set +u; shopt -s nullglob
  local candidates=()
  exact="$dir/$base"
  if [ -e "$exact" ]; then resolved="$(readlink -f "$exact" 2>/dev/null || true)"; [ -n "$resolved" ] && [ -e "$resolved" ] && candidates+=("$resolved"); fi
  for f in "$dir/$base".*; do [ -f "$f" ] && candidates+=("$f"); done
  shopt -u nullglob; set -u
  [ ${#candidates[@]} -gt 0 ] || return 1
  local lines=() v c; for c in "${candidates[@]}"; do v="$(get_version_suffix "$c" "$base")"; lines+=("$v"$'\t'"$c"); done
  printf "%s\n" "${lines[@]}" | LC_ALL=C sort -V -k1,1 | tail -n1 | cut -f2-
}
find_best_in_system(){
  local base="$1" best="" out paths c v
  if [ "$FAST" -eq 1 ]; then
    out="$(ldconfig_list || true)"
    if [ -n "${out:-}" ]; then
      paths="$(printf "%s\n" "$out" | grep -E "^[[:space:]]*${base}[[:space:]]" | sed 's@^.*=>[[:space:]]*@@')"
      if [ -n "$paths" ]; then
        local lines=(); while IFS= read -r c; do
          if [ -n "$c" ] && [ -e "$c" ]; then v="$(get_version_suffix "$c" "$base")"; lines+=("$v"$'\t'"$c"); fi
        done <<< "$paths"
        [ ${#lines[@]} -gt 0 ] && best="$(printf "%s\n" "${lines[@]}" | LC_ALL=C sort -V -k1,1 | tail -n1 | cut -f2-)"
      fi
    fi
  else
    out="$(ldconfig_list || true)"
    if [ -n "${out:-}" ]; then
      paths="$(printf "%s\n" "$out" | grep -E "^[[:space:]]*${base}[[:space:]]" | sed 's@^.*=>[[:space:]]*@@')"
      if [ -n "$paths" ]; then
        local lines=(); while IFS= read -r c; do
          if [ -n "$c" ] && [ -e "$c" ]; then v="$(get_version_suffix "$c" "$base")"; lines+=("$v"$'\t'"$c"); fi
        done <<< "$paths"
        [ ${#lines[@]} -gt 0 ] && best="$(printf "%s\n" "${lines[@]}" | LC_ALL=C sort -V -k1,1 | tail -n1 | cut -f2-)"
      fi
    fi
    if [ -z "$best" ]; then
      local p d; for d in "${system_dirs[@]}"; do
        p="$(find_best_in_dir "$d" "$base" 2>/dev/null || true)" || true
        [ -z "$p" ] && continue
        if [ -z "$best" ]; then best="$p"
        else if ver_lt "$(get_version_suffix "$best" "$base")" "$(get_version_suffix "$p" "$base")"; then best="$p"; fi
        fi
      done
    fi
  fi
  [ -n "$best" ] || return 1
  printf "%s\n" "$best"
}
safe_install(){ ensure_root; local src="$1" dst="$2"; if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] install -m 0644 \"$src\" \"$dst\""; else install -m 0644 "$src" "$dst"; fi }
backup_file(){ ensure_root; local p="$1" ts="$2"; [ -e "$p" ] || return 0; if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] cp -a \"$p\" \"${p}.bak.$ts\""; else cp -a "$p" "${p}.bak.$ts"; fi }
purge_bak(){
  ensure_root
  local days="$1"
  [ -d "$resolve_libs" ] || { err "Dossier introuvable: $resolve_libs"; exit 1; }
  title "Purge des sauvegardes"
  info "Recherche des backups (*.bak.*) de plus de $days jours…"
  mapfile -t candidates < <(find "$resolve_libs" -type f -name "*.bak.*" -mtime +"$days" -print 2>/dev/null || true)
  if [ ${#candidates[@]} -eq 0 ]; then ok "Aucun backup à purger."; exit 0; fi
  say "Candidats à supprimer :"; for f in "${candidates[@]}"; do say "  - $f"; done
  if confirm "Confirmer la suppression de ${#candidates[@]} fichier(s) ?"; then
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] suppression ignorée."
    else for f in "${candidates[@]}"; do rm -f "$f"; done; ok "Purge terminée."; fi
  else warn "Purge annulée."; fi
  exit 0
}

# ----- Auto-détection .run
RUN_SEARCH_DIRS=( "." "$PWD" "$HOME/Téléchargements" "$HOME/Downloads" )
is_resolve_run_name(){ printf "%s\n" "$(basename -- "$1")" | grep -Eq '^DaVinci_Resolve(_Studio)?_[0-9][0-9.]*_Linux\.run$'; }
collect_run_candidates(){
  local d f
  for d in "${RUN_SEARCH_DIRS[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.run; do [ -f "$f" ] || continue; is_resolve_run_name "$f" && printf "%s\n" "$f"; done
  done | awk '!seen[$0]++'
}
sort_run_candidates(){
  awk -F/ '{print $NF"\t"$0}' | awk '{ if (match($1, /Resolve(_Studio)?_([0-9.]+)_Linux\.run$/, m)) print m[2] "\t" $2; else print "0\t" $2 }' \
  | sort -V -k1,1 | awk -F'\t' '{print $2}'
}
auto_pick_runfile(){
  local candidates=(); mapfile -t candidates < <(collect_run_candidates | sort_run_candidates)
  local n="${#candidates[@]}"; [ "$n" -gt 0 ] || return 1
  if [ "$n" -eq 1 ]; then say "Installeur détecté : ${candidates[0]}"; confirm "Utiliser cet installeur ?" && printf "%s" "${candidates[0]}" || return 1
  else
    say "Plusieurs installeurs détectés :"; local i=1; for f in "${candidates[@]}"; do printf "  %d) %s\n" "$i" "$f"; i=$((i+1)); done
    printf "Sélection (1-%d, vide pour annuler) : " "$n"; read -r pick
    if printf '%s' "${pick:-}" | grep -Eq '^[0-9]+$' && [ "$pick" -ge 1 ] && [ "$pick" -le "$n" ]; then printf "%s" "${candidates[$((pick-1))]}"; else warn "Sélection annulée."; return 1; fi
  fi
}

# ----- Flows
run_uninstall_flow(){
  step "Désinstallation de DaVinci Resolve"
  if has_resolve; then
    if confirm "Confirmer la désinstallation ?"; then run_uninstaller || true; ok "Désinstallation (si confirmée) terminée."; else warn "Désinstallation annulée."; fi
  else warn "Resolve non détecté."; fi
}
show_versions_and_maybe_upgrade(){
  local runfile="$1" installed_ver="" installer_ver=""
  step "Détection des versions"
  if has_resolve && installed_ver="$(get_installed_resolve_version || true)"; then say "Version installée : ${installed_ver}"; else say "Resolve non détecté / version non lisible."; fi
  if [ -n "${runfile:-}" ]; then
    if installer_ver="$(parse_installer_version "$runfile" || true)"; then say "Version de l’installeur : ${installer_ver}"; else warn "Impossible de lire la version installeur: $runfile"; fi
  fi
  if [ -z "${runfile:-}" ] || [ -z "${installer_ver:-}" ]; then warn "Upgrade non lancé (installeur absent ou version non détectée)."; return 0; fi
  if [ -n "${installed_ver:-}" ] && ! ver_lt "$installed_ver" "$installer_ver"; then warn "Installeur (${installer_ver}) ≤ installé (${installed_ver})."; return 0; fi
  step "Mise à niveau Resolve"
  if has_resolve && confirm "Désinstaller la version actuelle (${installed_ver:-inconnue}) ?"; then run_uninstaller || true; else [ -n "${installed_ver:-}" ] && warn "Désinstallation annulée."; fi
  if confirm "Installer la nouvelle version (${installer_ver}) ?"; then run_installer "$runfile"; ok "Installation terminée (si confirmée)."; else warn "Installation annulée."; fi
  say "On passe au correctif des bibliothèques…"
}
run_upgrade_flow_cli(){ show_versions_and_maybe_upgrade "$UPGRADE_RUN"; run_fix_libs_flow; }
run_upgrade_flow_interactive(){
  step "Upgrade Resolve (.run)"
  say "Entrée vide → auto-détection (. /Téléchargements/Downloads)."
  printf "Chemin vers l'installeur .run : "; read -r UPGRADE_RUN
  if [ -z "${UPGRADE_RUN:-}" ]; then UPGRADE_RUN="$(auto_pick_runfile || true)"; [ -z "${UPGRADE_RUN:-}" ] && { warn "Aucun installeur trouvé."; return 0; }; fi
  show_versions_and_maybe_upgrade "$UPGRADE_RUN"; run_fix_libs_flow
}
run_fix_libs_flow(){
  step "Analyse des bibliothèques GLib de Resolve"
  [ -d "$resolve_libs" ] || { err "Dossier introuvable: $resolve_libs (Resolve est-il installé ?)"; return 1; }
  say "Distro : $family"; say "Répertoires système scannés : ${system_dirs[*]}"; say ""
  report_missing=(); report_outdated=(); declare -A rep_res rep_sys sys_file res_file
  for base in "${bases[@]}"; do
    res_best="$(find_best_in_dir "$resolve_libs" "$base" 2>/dev/null || true)" || true
    sys_best="$(find_best_in_system "$base" 2>/dev/null || true)" || true
    if [ -z "${sys_best:-}" ]; then warn "$base : aucune version trouvée côté système."; continue; fi
    sys_ver="$(get_version_suffix "$sys_best" "$base")"; rep_sys["$base"]="$sys_ver"; sys_file["$base"]="$sys_best"
    if [ -z "${res_best:-}" ]; then say "  $base : manquant (système: $sys_ver)"; report_missing+=("$base"); continue; fi
    res_ver="$(get_version_suffix "$res_best" "$base")"; rep_res["$base"]="$res_ver"; res_file["$base"]="$res_best"
    printf "  %-22s resolve: %-12s système: %-12s\n" "$base" "$res_ver" "$sys_ver"
    if ver_lt "$res_ver" "$sys_ver"; then report_outdated+=("$base"); fi
  done
  hr; say "RÉSUMÉ :"
  if [ ${#report_missing[@]} -gt 0 ]; then say "  Manquants :"; for b in "${report_missing[@]}"; do say "    - $b (système: ${rep_sys[$b]})"; done; else ok "  Aucun fichier manquant."; fi
  if [ ${#report_outdated[@]} -gt 0 ]; then say "  Plus anciens :"; for b in "${report_outdated[@]}"; do say "    - $b (resolve: ${rep_res[$b]} < système: ${rep_sys[$b]})"; done; else ok "  Aucune version plus ancienne détectée."; fi
  hr
  if [ ${#report_missing[@]} -gt 0 ]; then
    step "Copie des manquants"
    if confirm "Copier les fichiers manquants vers $resolve_libs ?"; then
      say "Validation :"; for b in "${report_missing[@]}"; do say "  - $b -> $(basename "${sys_file[$b]}")"; done
      if confirm "Confirmer la copie ?"; then for b in "${report_missing[@]}"; do src="${sys_file[$b]}"; dst="$resolve_libs/$(basename "$src")"; say "Copie $src -> $dst"; safe_install "$src" "$dst"; done; ok "Copie terminée."; else warn "Copie annulée."; fi
    else warn "Copie refusée."; fi
  fi
  if [ ${#report_outdated[@]} -gt 0 ]; then
    step "Remplacement des obsolètes"
    if confirm "Remplacer par les versions système plus récentes ?"; then
      say "Validation :"; for b in "${report_outdated[@]}"; do say "  - $b : ${rep_res[$b]} -> ${rep_sys[$b]}"; done
      if confirm "Confirmer le remplacement ?"; then
        ts="$(date +%Y%m%d-%H%M%S)"
        for b in "${report_outdated[@]}"; do
          src="${sys_file[$b]}"; dst="$resolve_libs/$(basename "$src")"
          if [ -n "${res_file[$b]:-}" ] && [ -e "${res_file[$b]}" ]; then say "Sauvegarde: ${res_file[$b]} -> ${res_file[$b]}.bak.$ts"; backup_file "${res_file[$b]}" "$ts"; fi
          say "Remplacement: $src -> $dst"; safe_install "$src" "$dst"
        done
        if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled && command -v restorecon >/dev/null 2>&1; then [ "$DRY_RUN" -eq 1 ] && info "[dry-run] restorecon -R \"$resolve_libs\"" || restorecon -R "$resolve_libs" || true; fi
        ok "Remplacement terminé."
      else warn "Remplacement annulé."; fi
    else warn "Remplacement refusé."; fi
  fi
  say ""; ok "Terminé."
}

# ----- Menu (boucle)
# ====== Menu (robuste via 'select') ======
show_menu_header() {
  title "rupdate.sh v${SCRIPT_VERSION} — Menu interactif"
  printf "Distro détectée : %s\n" "$family"
  printf "Répertoires scannés : %s\n\n" "${system_dirs[*]}"
}

menu_loop() {
  while true; do
    show_menu_header
    PS3="Choix (1-6) : "
    select item in \
      "Vérifier uniquement (rapport complet)" \
      "Corriger les bibliothèques (copie / remplacement)" \
      "Upgrade Resolve depuis un .run (auto-détection possible)" \
      "Désinstaller Resolve" \
      "Purger les sauvegardes (.bak) > 90 jours" \
      "Quitter"; do
      case $REPLY in
        1) DRY_RUN=1; run_fix_libs_flow; DRY_RUN=0; break ;;
        2) run_fix_libs_flow; break ;;
        3) run_upgrade_flow_interactive; break ;;
        4) run_uninstall_flow; break ;;
        5) PURGE_BAK=${PURGE_BAK:-90}; purge_bak "$PURGE_BAK" ;;  # purge_bak fait exit 0
        6) ok "Au revoir 👋"; exit 0 ;;
        *) warn "Choix invalide."; break ;;
      esac
    done
    printf "\n(Entrée pour revenir au menu)… "
    read -r _ || true
    clear 2>/dev/null || true
  done
}

# ====== Main (fin) ======
title "Démarrage rupdate.sh v${SCRIPT_VERSION}"
say "Options : $([ "$DRY_RUN" -eq 1 ] && printf "dry-run ")$([ "$FAST" -eq 1 ] && printf "fast ")$([ "$NO_LDCONFIG" -eq 1 ] && printf "no-ldconfig ")$([ "$ASSUME_YES" -eq 1 ] && printf "yes-mode ")$([ "$QUIET" -eq 1 ] && printf "quiet ")$([ "$DEBUG" -eq 1 ] && printf "debug ")"
say "Dossier Resolve : $resolve_libs"
say ""

# Exécutions non-interactives directes
if [ -n "${PURGE_BAK:-}" ] && [ "$SHOW_MENU" -eq 0 ]; then purge_bak "$PURGE_BAK"; fi
if [ "$UNINSTALL_ONLY" -eq 1 ] && [ "$SHOW_MENU" -eq 0 ]; then run_uninstall_flow; exit 0; fi
if [ -n "${UPGRADE_RUN:-}" ] || [ "$VERSION_ONLY" -eq 1 ]; then
  if [ "$VERSION_ONLY" -eq 1 ] && [ -z "${UPGRADE_RUN:-}" ]; then
    step "Versions"
    if has_resolve && v="$(get_installed_resolve_version || true)"; then
      say "Version installée : $v"
    else
      say "Resolve non détecté / version non lisible."
    fi
    exit 0
  fi
  run_upgrade_flow_cli
  [ "$SHOW_MENU" -eq 0 ] && exit 0
fi

# Sinon, menu interactif robuste
menu_loop

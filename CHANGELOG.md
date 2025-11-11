# 🧾 Changelog — rupdate.sh

Toutes les modifications notables de ce projet seront documentées dans ce fichier.  
Le format s’inspire du standard [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)  
et de la sémantique de version [SemVer](https://semver.org/lang/fr/).

---

## [v1.3.2] — 2025-11-11
### 🔧 Améliorations
- Nouveau **menu interactif robuste** basé sur `select` (fonctionne sous `sudo` et toutes consoles).
- Boucle persistante : l’utilisateur peut enchaîner plusieurs opérations sans relancer le script.
- Nettoyage du code, affichage simplifié et plus verbeux.
- Correction des variables `SHOW_MENU` et du comportement sous openSUSE.

### 🧠 Technique
- Meilleure compatibilité shell (`#!/bin/bash` conseillé).
- Sortie standard uniformisée (`say`, `ok`, `warn`, `err`).
- Préparation d’un futur mode couleur/TUI.

---

## [v1.3.1] — 2025-11-10
### 🚀 Nouvelles fonctions
- Détection automatique des installeurs `.run` dans `.` / `~/Téléchargements` / `~/Downloads`.
- Comparaison de version entre installeur et version installée.
- Désinstallation et réinstallation guidées de Resolve.
- Nettoyage des `.bak` avec confirmation et option `--purge-bak`.

### 🐛 Corrections
- Suppression des `exit` intempestifs dans les sous-fonctions.
- Gestion plus fiable du `sudo` et des confirmations.
- Passage de la détection de distribution à une méthode stable (`/etc/os-release`).

---

## [v1.3.0] — 2025-11-09
### ✨ Ergonomie
- Introduction du **menu interactif** et des choix d’action.
- Affichage amélioré (titres, étapes, résumé clair).

### ⚙️ Interne
- Refactorisation complète du code pour le rendre modulaire (fonctions `run_*_flow`).
- Adoption du style verbeux + confirmations utilisateur systématiques.

---

## [v1.2] — 2025-11-08
### 🔍 Fonctionnalités
- Vérification de la présence des fichiers `libgio`, `libglib`, `libgmodule`, `libgobject`.
- Copie automatique des fichiers manquants depuis le système.
- Comparaison de versions et remplacement conditionnel.
- Sauvegardes automatiques `.bak.<timestamp>` avant remplacement.

---

## [v1.0] — 2025-11-07
### 🎉 Première version publique
- Script initial pour DaVinci Resolve sous Linux.
- Comparaison simple entre `/opt/resolve/libs` et `/usr/lib*/`.
- Correction des bibliothèques glib fournies par Blackmagic.
- Licence MIT.

---

## 📜 Licence
MIT — libre, modifiable et redistribuable.  
© 2025 **Ben6219**

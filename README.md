[![ShellCheck](https://github.com/Ben6219/rupdate/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Ben6219/rupdate/actions/workflows/shellcheck.yml)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-1.3.2-brightgreen.svg)


# 🧩 rupdate.sh

**rupdate.sh** est un script libre (licence MIT) permettant de **corriger automatiquement les bibliothèques GLib** utilisées par *DaVinci Resolve* sous Linux.  
Il gère également la **détection automatique des installeurs `.run`**, la **désinstallation** et la **mise à niveau** de Resolve, ainsi qu’une **interface de menu simple et claire**.

---

## ✨ Fonctionnalités

- 🔍 Compare les bibliothèques de `/opt/resolve/libs` avec celles du système.  
- 🧱 Copie les fichiers manquants et remplace les versions obsolètes.  
- 🗂️ Sauvegarde automatique (`.bak.YYYYmmdd-HHMMSS`).  
- 💾 Auto-détection des installeurs `.run` dans `.` / `~/Téléchargements` / `~/Downloads`.  
- 🌀 Menu interactif persistant (v1.3.2, robuste sous sudo).  
- 🧹 Purge des anciennes sauvegardes.  
- 🔁 Mise à jour / désinstallation complète de Resolve.

---

## 🧠 Compatibilité

✅ Testé sur :
- openSUSE Tumbleweed (référence)
- Fedora Workstation
- Ubuntu / Debian
- Arch Linux / Manjaro
- Gentoo

> ⚠️ Les systèmes à base AMDGPU-Pro sont parfois instables avec Resolve.  
> La meilleure stabilité est observée sur plateformes **NVIDIA + openSUSE / Fedora**.

---

## 🧩 Installation

```bash
git clone https://github.com/Ben6219/rupdate.git
cd rupdate
chmod +x rupdate.sh
sudo ./rupdate.sh

# 🧩 rupdate.sh — Synchroniseur de bibliothèques pour DaVinci Resolve sous Linux

## 🎬 Présentation
**rupdate.sh** est un script Bash libre conçu pour les utilisateurs Linux de **DaVinci Resolve**, afin de synchroniser automatiquement les bibliothèques `libglib`, `libgio`, `libgmodule` et `libgobject` entre le dossier d’installation de Resolve (`/opt/resolve/libs`) et les versions système.

Il vérifie les versions installées, copie les fichiers manquants, remplace les plus anciens par les plus récents, et crée des sauvegardes automatiques `.bak.YYYYmmdd-HHMMSS`.

## ⚙️ Fonctionnalités principales
- Détection automatique de la distribution
- Comparaison complète des versions
- Copie et remplacement automatiques avec sauvegarde
- Vérification simple avec `--check`
- Support de `ldconfig -p` et fallback sur les répertoires systèmes
- Licence MIT libre et ouverte

## 🧪 Options disponibles
| Option | Description |
|:--------|:-------------|
| `--check` | Lecture seule (aucune modification) |
| `--yes` | Répond automatiquement “oui” à toutes les confirmations |
| `--no-ldconfig` | N’utilise pas `ldconfig -p` |
| `--fast` | Utilise uniquement `ldconfig -p` |
| `--purge-bak [JOURS]` | Supprime les backups `.bak.*` plus anciens que *JOURS* (90 par défaut) |
| `-h`, `--help` | Affiche l’aide |

## ⚖️ Licence (MIT)
© 2025 — Collaboration entre *Ben6219* & *ChatGPT*

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

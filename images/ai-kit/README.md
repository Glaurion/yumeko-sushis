# Kit Images Uniformes (Menu YUMEKO)

Ce dossier contient le kit pour garder toutes les images du menu avec un style uniforme.

## Fichiers

- `prompts-menu.json`: prompts issus du mode uniformisation locale.
- `prompts-menu-openai.json`: prompts utilises par la generation 100% IA OpenAI.

## Mode 1: Uniformiser les images existantes (rapide)

Script:

- `C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\uniform-images-kit.ps1`

Ce script:

1. lit les articles dans `index.html`,
2. cree une sauvegarde des images d'origine,
3. regenere toutes les images avec le meme fond et le meme format carre.

Commande:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\uniform-images-kit.ps1"
```

## Mode 2: Generation 100% IA de tout le menu (OpenAI)

Script:

- `C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\generate-menu-images-openai.ps1`

Pre-requis:

1. Une cle API OpenAI active
2. Variable d'environnement `OPENAI_API_KEY`

Commande:

```powershell
$env:OPENAI_API_KEY="ta_cle_api_openai"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\generate-menu-images-openai.ps1"
```

Mode test (n'ecrit pas les images):

```powershell
& "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\generate-menu-images-openai.ps1" -DryRun
```

## Sauvegardes

Chaque execution cree un dossier de sauvegarde:

- `images/_backup-uniform-YYYYMMDD-HHMMSS`
- `images/_backup-openai-YYYYMMDD-HHMMSS`

Tu peux restaurer facilement les images d'origine depuis ces dossiers si besoin.

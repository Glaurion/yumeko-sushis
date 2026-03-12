# Kit Images Uniformes (Menu YUMEKO)

Ce dossier contient le kit pour garder toutes les images du menu avec un style uniforme.

## Fichiers

- `prompts-menu.json`: liste complete des prompts (1 prompt par article du menu).

## Regeneration rapide des images

Le script principal est:

- `C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\uniform-images-kit.ps1`

Ce script:

1. lit les articles dans `index.html`,
2. cree une sauvegarde des images d'origine,
3. regenere toutes les images avec le meme fond et le meme format carre,
4. met a jour automatiquement `prompts-menu.json`.

Commande:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& "C:\Users\Benjamin_DHINAUT\Documents\GitHub\yumeko-sushis\scripts\uniform-images-kit.ps1"
```

## Sauvegardes

Chaque execution cree un dossier de sauvegarde:

- `images/_backup-uniform-YYYYMMDD-HHMMSS`

Tu peux restaurer facilement les images d'origine depuis ce dossier si besoin.

## IA complete (optionnel)

`prompts-menu.json` est pret pour une generation IA 100% nouvelle image (OpenAI, Midjourney, etc.).
Il suffit de garder exactement les memes noms de fichiers (`m1.jpg`, `c1.jpg`, etc.) pour que le site affiche tout sans autre modification.

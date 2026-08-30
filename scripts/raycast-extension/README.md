# Extension Raycast — Articles Nicolasfurno.fr

Cette extension locale fournit une interface Raycast native au générateur d’articles du dépôt.

## Installation

Prérequis : Raycast, Node.js 22.14 ou plus récent, npm 7 ou plus récent, ainsi que les dépendances du générateur d’articles.

```sh
cd scripts/raycast-extension
npm install
npm run dev
```

Dans les préférences de la commande **Nouvel Article**, renseigner le chemin absolu de la racine du dépôt, c’est-à-dire le dossier qui contient `hugo.toml`.

L’extension reste enregistrée dans Raycast après l’arrêt de `npm run dev`. Relancer cette commande pour développer avec le rechargement automatique.

## Validation

```sh
npm test
npm run lint
npm run build
```

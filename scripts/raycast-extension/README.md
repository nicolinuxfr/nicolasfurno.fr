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

Après activation du hook Git du dépôt, un `git pull` qui modifie des fichiers sous `scripts/raycast-extension/` laissera le watcher existant recharger les fichiers, ou en démarrera un en arrière-plan s’il n’est pas actif. Active le hook une fois dans chaque clone avec :

```sh
git config core.hooksPath .githooks
```

Le journal du watcher en arrière-plan se trouve dans le répertoire temporaire système sous `nicolasfurno-raycast-extension.log`.

## Validation

```sh
npm test
npm run lint
npm run build
```

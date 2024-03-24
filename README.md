# Le blog de Nicolas Furno

Adresse du site : [https://nicolasfurno.fr](https://nicolasfurno.fr)

N’hésitez pas à [ouvrir une *issue*](https://github.com/nicolinuxfr/nicolasfurno.fr/issues) si vous repérez une erreur dans un article. Vous pouvez même ouvrir une [*pull-request*](https://github.com/nicolinuxfr/nicolasfurno.fr/pulls) et je l’utiliserai pour corriger une coquille. 

## Côté technique

Blog créé avec le générateur de sites statiques [Hugo](https://github.com/gohugoio/hugo). Thème créé par mes soins, son code source est disponible [également sur GitHub](https://github.com/nicolinuxfr/nicolasfurno).

Hébergement sur GitHub Pages.

Le thème est *open-source* et peut-être réutilisé librement. En revanche, tout le contenu reste exclusivement ma propriété et ne peut pas être reproduit sans mon autorisation.

## Changer les clés MapKit JS

**Expiration : 24 mars 2025**

- Générer une nouvelle clé privée MapKit.JS et la télécharger : https://developer.apple.com/account/resources/authkeys/list
- Générer les nouvelles clés publiques : https://maps.developer.apple.com/token-maker
- Générer une sans restriction de domaine pour les tests et l'utiliser dans le fichier `.envrc`
- Générer une autre avec le domaine du blog et modifier les secrets GitHub : https://github.com/nicolinuxfr/nicolasfurno.fr/settings/secrets/actions

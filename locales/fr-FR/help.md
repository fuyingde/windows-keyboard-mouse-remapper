# Mappage des touches {#mapping}

## Utilisation de base {#mapping-basic}

Le mappage des touches transforme une touche ou une combinaison en une autre touche ou combinaison.

### Mode d'emploi

1. Sélectionnez « Ajouter un mappage » à gauche.
2. Enregistrez successivement les combinaisons d'entrée et de sortie. Chacune peut contenir jusqu'à trois touches.
3. Vérifiez les combinaisons affichées, sélectionnez « Enregistrer », puis cochez la case du mappage pour l'activer.

> Définissez la sortie sur « Aucun » et activez le mappage pour bloquer la touche d'entrée. Décochez la case pour rétablir immédiatement le fonctionnement normal de cette touche.

## Règles des combinaisons {#mapping-combo}

- Les combinaisons d'entrée et de sortie peuvent contenir d'une à trois touches.
- Échap peut servir de touche d'entrée ou de sortie normale.
- Le mappage se déclenche dès que la dernière touche d'entrée est enfoncée et la sortie est relâchée dès qu'une touche d'entrée est relâchée.
- Les entrées à une, deux ou trois touches ne peuvent pas présenter de conflits de préfixe. Par exemple, Ctrl et Ctrl+C ne peuvent pas être enregistrés simultanément.
- Les combinaisons de sortie ne sont pas vérifiées pour les doublons ou les préfixes. Plusieurs mappages peuvent donc utiliser la même sortie.
- Une direction de molette ne peut être que la dernière touche d'une combinaison.

## Restrictions des boutons de souris {#mapping-mouse}

- Les boutons gauche et droit de la souris ne peuvent pas être mappés seuls ni utilisés comme première touche d'une combinaison.
- Après avoir appuyé sur une autre touche, le bouton gauche ou droit peut être enregistré comme deuxième ou troisième touche.
- Les autres mappages sont suspendus pendant l'enregistrement. Les boutons gauche et droit continuent à fonctionner normalement en dehors du champ d'enregistrement actif.
- L'enregistrement est autorisé uniquement lorsque l'outil de mappage clavier-souris est au premier plan. Changer de fenêtre, réduire ou masquer l'application termine l'enregistrement : les touches virtuelles déjà choisies sont validées, sinon l'enregistrement est annulé.

## Clavier virtuel {#mapping-virtual}

- Utilisez « Clavier virtuel » à gauche de l'aide dans la barre de titre pour ouvrir un clavier standard 104 touches. « Masquer le clavier » le ferme.
- Le clavier s'ancre par défaut en bas de la fenêtre. Si la zone de travail de l'écran est trop basse, il devient un panneau flottant déplaçable.
- Les touches virtuelles s'écrivent uniquement dans le champ de mappage en cours d'enregistrement. Elles ne sont pas envoyées au système et ne déclenchent pas les mappages enregistrés.
- Activez d'abord un champ d'enregistrement d'entrée ou de sortie. Un clic sur une touche virtuelle hors enregistrement demande d'activer d'abord la saisie.
- « Valider » au-dessus du pavé numérique n'est disponible qu'après un clic sur une touche virtuelle. Après une ou deux touches, « Valider » termine l'enregistrement. Trois touches se valident automatiquement.
- Les touches physiques et virtuelles peuvent être mélangées dans l'ordre des appuis. Après une touche virtuelle, relâcher une touche physique ne termine pas l'enregistrement. Validez, atteignez trois touches ou cliquez hors du champ.
- Un clic dans le vide, un changement de fenêtre, une réduction ou un masquage termine l'enregistrement : les touches virtuelles déjà choisies sont validées, sinon l'enregistrement est annulé.

# Paramètres {#settings}

## Démarrage, zone de notification et langue {#settings-general}

- « Démarrer avec Windows » lance automatiquement l'application après l'ouverture de session.
- Fermer la fenêtre masque l'application tandis que les mappages activés continuent de fonctionner.
- Cliquez avec le bouton gauche sur l'icône de notification pour réafficher la fenêtre ; utilisez son menu contextuel pour quitter complètement.
- Si vous masquez l'icône de notification, relancez l'application pour restaurer la fenêtre existante.
- Un changement de langue actualise immédiatement le titre, l'interface, les messages et le menu de notification sans interrompre les mappages.

## Interrupteur général des mappages {#settings-input}

- Désactiver l'interrupteur de mappage dans la barre de titre relâche immédiatement les sorties maintenues et désactive tous les mappages.
- Lorsqu'il est désactivé, toutes les touches du clavier et tous les boutons de la souris retrouvent leur fonction d'origine. Le réactiver remet en service les mappages sélectionnés.
- Cet interrupteur est temporaire et se réactive à chaque démarrage de l'application.

## Toujours au premier plan {#settings-topmost}

- Utilisez le bouton en forme d'épingle pour garder la fenêtre au-dessus des fenêtres normales. Sélectionnez-le à nouveau pour désactiver ce comportement.

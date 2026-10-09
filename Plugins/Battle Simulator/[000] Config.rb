#===============================================================================
# Battle Simulator - Configuration
#===============================================================================
module BattleSimulator
  # Si true, le jeu saute l'écran titre et l'aventure et ouvre directement le
  # menu du simulateur.
  ENABLED = true
  # Touche à maintenir pendant le démarrage pour lancer le jeu normal (écran
  # titre, aventure, outils de debug). Input::SPECIAL = la touche "Special" de
  # la fenêtre des touches (F1). Pas CTRL ni SHIFT : en mode Debug, Essentials
  # les utilise au démarrage pour forcer la recompilation.
  NORMAL_GAME_KEY = Input::SPECIAL

  # Fichier des équipes, au format d'export de Pokémon Showdown, relatif au
  # dossier du jeu. Il est relu à chaque combat : pas besoin de recompiler.
  TEAMS_FILE   = "BattleSim/teams.txt"
  # Mémorise les derniers réglages du menu (format, équipes, gimmicks cochés).
  SESSION_FILE = "BattleSim/last_session.txt"

  # Niveau utilisé quand un Pokémon n'a pas de ligne "Level:" (Showdown : 100).
  DEFAULT_LEVEL = 100

  # Joueur
  PLAYER_NAME         = "Joueur"
  PLAYER_CHARACTER_ID = 1   # ID de PBS/metadata.txt [1], [2]... (sprite de dos)

  # Dresseur contrôlé par l'IA. Le type doit exister dans PBS/trainer_types.txt.
  # Son SkillLevel (= BaseMoney par défaut) règle l'IA : 100+ = meilleure IA.
  AI_TRAINER_TYPE = :CHAMPION
  AI_TRAINER_NAME = "Boss"
  AI_LOSE_TEXT    = "Bien joué..."

  # Donne un Méga-Anneau au joueur et à l'IA pour autoriser la Méga-Évolution.
  ALLOW_MEGA_EVOLUTION = true

  # Décor EBDX : une constante de EnvironmentEBDX (ex. :STAGE, :INDOOR,
  # :CHAMPION) ou nil pour le décor par défaut de la carte.
  EBDX_BACKDROP = nil

  # Musique du menu (nom d'un fichier de Audio/BGM). nil = musique de l'écran
  # titre définie dans RPG Maker.
  MENU_BGM = nil

  # Affiche les gimmicks de démonstration de l'étape 1 (tests du moteur). À
  # passer à false quand les vrais gimmicks seront en place.
  SHOW_DEMO_MODIFIERS = true
end

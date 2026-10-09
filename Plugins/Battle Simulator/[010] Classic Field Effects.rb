#===============================================================================
# Étape 2 - effets classiques permanents.
#
# Météo et terrain : ce sont la météo et le terrain "par défaut" du combat
# (comme la pluie d'une carte pluvieuse) : ils sont là dès le début et durent
# tout le combat. Avec CLASSIC_EFFECTS_REMOVABLE = true (réglage par défaut),
# une attaque ou un talent peut les remplacer 5 tours (Danse Pluie,
# Crachin...) ou retirer le terrain (Anti-Brume, Lames Ferraille...) : la
# météo revient quand l'autre se termine, le terrain revient à la fin du tour.
#
# Salles et Gravité : verrouillées, utiliser la même attaque échoue.
#
# Protections côté IA : présentes dès le tour 1 et sans fin. Casse-Brique,
# Anti-Brume, Lame de Fond, Change Côté... peuvent les retirer : elles se
# reforment à la fin du tour (ou jamais retirées si
# CLASSIC_EFFECTS_REMOVABLE = false).
#===============================================================================
module BattleSimulator
  module ClassicEffects
    module_function

    def strict?
      return !BattleSimulator::CLASSIC_EFFECTS_REMOVABLE
    end

    # Phrase ajoutée aux descriptions selon le réglage.
    def weather_rule
      return _INTL("Ne peut pas être remplacée (sauf par une météo primale).") if strict?
      return _INTL("Une autre météo peut la remplacer 5 tours, puis elle revient.")
    end

    def terrain_rule
      return _INTL("Ne peut être ni remplacé ni retiré.") if strict?
      return _INTL("Remplaçable 5 tours ; retiré (Anti-Brume...), il revient en fin de tour.")
    end

    def side_rule
      return _INTL("Ne peut pas être retiré.") if strict?
      return _INTL("Retiré (Casse-Brique, Anti-Brume...), il revient en fin de tour.")
    end

    def register_weather(id, name, weather, text, order)
      BattleModifiers.register(id,
        name:        name,
        description: text + " " + weather_rule,
        category:    :weather,
        scope:       :global,
        exclusive:   :weather,
        order:       order
      ) do |m|
        m.on(:on_battle_init) do |battle|
          BattleModifiers::Locks.lock_weather(battle, weather,
            strict:        strict?,
            block_message: _INTL("Mais la météo permanente ne change pas !"))
        end
      end
    end

    def register_terrain(id, name, terrain, text, order)
      BattleModifiers.register(id,
        name:        name,
        description: text + " " + terrain_rule,
        category:    :terrain,
        scope:       :global,
        exclusive:   :terrain,
        order:       order
      ) do |m|
        m.on(:on_battle_init) do |battle|
          BattleModifiers::Locks.lock_terrain(battle, terrain,
            strict:        strict?,
            block_message: _INTL("Mais le terrain permanent ne change pas !"))
        end
      end
    end

    def register_room(id, name, effect, text, announce, order)
      BattleModifiers.register(id,
        name:        name,
        description: text,
        category:    :room,
        scope:       :global,
        order:       order
      ) do |m|
        m.on(:on_battle_init) do |battle|
          BattleModifiers::Locks.lock_field_effect(battle, effect)
        end
        m.on(:on_battle_start) { |battle| battle.pbDisplay(announce) }
      end
    end

    def register_side(id, name, effect, text, announce, order)
      BattleModifiers.register(id,
        name:        name,
        description: text + " " + side_rule,
        category:    :ai_side,
        scope:       :ai_side,
        order:       order
      ) do |m|
        m.on(:on_battle_init) do |battle|
          BattleModifiers::Locks.lock_side_effect(battle, 1, effect, strict?)
        end
        m.on(:on_battle_start) { |battle| battle.pbDisplay(announce) }
      end
    end
  end
end

#-------------------------------------------------------------------------------
# Météo
#-------------------------------------------------------------------------------
BattleSimulator::ClassicEffects.register_weather(:perm_sun,
  _INTL("Soleil permanent"), :Sun,
  _INTL("Soleil tout le combat : Feu x1,5, Eau x0,5."), 0)
BattleSimulator::ClassicEffects.register_weather(:perm_rain,
  _INTL("Pluie permanente"), :Rain,
  _INTL("Pluie tout le combat : Eau x1,5, Feu x0,5."), 1)
BattleSimulator::ClassicEffects.register_weather(:perm_sandstorm,
  _INTL("Tempête de sable permanente"), :Sandstorm,
  _INTL("Sable tout le combat : 1/16 PV par tour (sauf Roche/Sol/Acier), Déf. Spé. Roche x1,5."), 2)
BattleSimulator::ClassicEffects.register_weather(:perm_hail,
  _INTL("Grêle permanente"), :Hail,
  _INTL("Grêle + Neige tout le combat : 1/16 PV par tour (sauf Glace), Défense des types Glace x1,5."), 3)
BattleSimulator::ClassicEffects.register_weather(:perm_harsh_sun,
  _INTL("Terre Finale (Soleil intense)"), :HarshSun,
  _INTL("Soleil intense tout le combat : les attaques Eau échouent, Feu x1,5."), 4)
BattleSimulator::ClassicEffects.register_weather(:perm_heavy_rain,
  _INTL("Mer Primaire (Pluie battante)"), :HeavyRain,
  _INTL("Pluie battante tout le combat : les attaques Feu échouent, Eau x1,5."), 5)
BattleSimulator::ClassicEffects.register_weather(:perm_strong_winds,
  _INTL("Souffle Delta (Vents violents)"), :StrongWinds,
  _INTL("Vents violents tout le combat : plus de faiblesses du type Vol."), 6)

#-------------------------------------------------------------------------------
# Terrains
#-------------------------------------------------------------------------------
BattleSimulator::ClassicEffects.register_terrain(:perm_electric_terrain,
  _INTL("Champ Électrifié permanent"), :Electric,
  _INTL("Électrik x1,3 et pas de sommeil pour les Pokémon au sol."), 0)
BattleSimulator::ClassicEffects.register_terrain(:perm_psychic_terrain,
  _INTL("Champ Psychique permanent"), :Psychic,
  _INTL("Psy x1,3, les Pokémon au sol ne subissent pas les attaques prioritaires."), 1)
BattleSimulator::ClassicEffects.register_terrain(:perm_grassy_terrain,
  _INTL("Champ Herbu permanent"), :Grassy,
  _INTL("Plante x1,3 et 1/16 PV soignés par tour au sol ; Séisme, Piétisol et Ampleur réduits."), 2)
BattleSimulator::ClassicEffects.register_terrain(:perm_misty_terrain,
  _INTL("Champ Brumeux permanent"), :Misty,
  _INTL("Dragon x0,5 contre les Pokémon au sol, qui sont aussi protégés des statuts."), 3)

#-------------------------------------------------------------------------------
# Salles et Gravité
#-------------------------------------------------------------------------------
BattleSimulator::ClassicEffects.register_room(:perm_trick_room,
  _INTL("Distorsion permanente"), PBEffects::TrickRoom,
  _INTL("Les Pokémon les plus lents agissent en premier pendant tout le combat. Utiliser Distorsion échoue."),
  _INTL("Les dimensions sont déformées pour tout le combat !"), 0)
BattleSimulator::ClassicEffects.register_room(:perm_magic_room,
  _INTL("Zone Magique permanente"), PBEffects::MagicRoom,
  _INTL("Aucun objet tenu ne fonctionne pendant tout le combat (des deux côtés). Utiliser Zone Magique échoue."),
  _INTL("Une zone étrange rend les objets inutilisables pour tout le combat !"), 1)
BattleSimulator::ClassicEffects.register_room(:perm_wonder_room,
  _INTL("Zone Étrange permanente"), PBEffects::WonderRoom,
  _INTL("Défense et Défense Spéciale sont échangées pendant tout le combat. Utiliser Zone Étrange échoue."),
  _INTL("Défense et Défense Spéciale sont échangées pour tout le combat !"), 2)
BattleSimulator::ClassicEffects.register_room(:perm_gravity,
  _INTL("Gravité permanente"), PBEffects::Gravity,
  _INTL("Plus personne ne vole (Sol touche tout le monde), précision x5/3, Vol, Rebond... impossibles."),
  _INTL("La gravité s'intensifie pour tout le combat !"), 3)

#-------------------------------------------------------------------------------
# Protections côté IA
#-------------------------------------------------------------------------------
BattleSimulator::ClassicEffects.register_side(:ai_reflect,
  _INTL("Protection"), PBEffects::Reflect,
  _INTL("Dégâts physiques reçus par l'IA réduits (x0,5, x0,67 en Duo)."),
  _INTL("L'équipe adverse est protégée par Protection !"), 0)
BattleSimulator::ClassicEffects.register_side(:ai_light_screen,
  _INTL("Mur Lumière"), PBEffects::LightScreen,
  _INTL("Dégâts spéciaux reçus par l'IA réduits (x0,5, x0,67 en Duo)."),
  _INTL("L'équipe adverse est protégée par Mur Lumière !"), 1)
BattleSimulator::ClassicEffects.register_side(:ai_aurora_veil,
  _INTL("Voile Aurore"), PBEffects::AuroraVeil,
  _INTL("Tous les dégâts reçus par l'IA réduits (sans grêle requise). Ne se cumule pas avec Protection/Mur Lumière."),
  _INTL("L'équipe adverse est protégée par Voile Aurore !"), 2)
BattleSimulator::ClassicEffects.register_side(:ai_tailwind,
  _INTL("Vent Arrière"), PBEffects::Tailwind,
  _INTL("Vitesse de l'équipe IA doublée."),
  _INTL("Un vent arrière souffle derrière l'équipe adverse !"), 3)
BattleSimulator::ClassicEffects.register_side(:ai_safeguard,
  _INTL("Rune Protect"), PBEffects::Safeguard,
  _INTL("L'IA est protégée des statuts et de la confusion infligés par les attaques adverses."),
  _INTL("L'équipe adverse est protégée par Rune Protect !"), 4)
BattleSimulator::ClassicEffects.register_side(:ai_mist,
  _INTL("Brume"), PBEffects::Mist,
  _INTL("Les stats de l'IA ne peuvent pas être baissées par l'adversaire."),
  _INTL("L'équipe adverse est enveloppée de Brume !"), 5)
BattleSimulator::ClassicEffects.register_side(:ai_lucky_chant,
  _INTL("Air Veinard"), PBEffects::LuckyChant,
  _INTL("L'IA ne peut pas subir de coups critiques."),
  _INTL("L'équipe adverse est protégée des coups critiques par Air Veinard !"), 6)

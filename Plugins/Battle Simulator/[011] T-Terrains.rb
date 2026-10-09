#===============================================================================
# Étape 3 - T-Terrains (terrains de niveau 2).
#
# Un T-Terrain est le vrai Champ correspondant (tous ses effets habituels
# restent : sommeil impossible, priorité bloquée, statuts bloqués...) avec des
# effets renforcés, et il est verrouillé :
#   - il est là dès le début et dure tout le combat ;
#   - Anti-Brume, Lames Ferraille, Pirouette Glace, Téra-Fusion Zéro ne
#     l'enlèvent pas ;
#   - les autres terrains (attaques et talents Créa-...) ne le remplacent pas.
#     On ne peut cocher qu'un T-Terrain à la fois, il reste donc tout le
#     combat ;
#   - s'il disparaissait malgré tout, il revient à la prochaine entrée en jeu,
#     après une attaque ou en fin de tour.
#
# Les effets renforcés du T-Terrain s'appliquent à tous les Pokémon, même ceux
# qui ne touchent pas le sol (type Vol, Lévitation...).
#===============================================================================
module BattleSimulator
  module TTerrains
    # Bonus du Champ classique pour les Pokémon au sol (174_Move_Usage...).
    CLASSIC_BOOST = (Settings::MECHANICS_GENERATION >= 8) ? 1.3 : 1.5

    module_function

    def active?(battle, terrain)
      return BattleModifiers::Locks.terrain_active?(battle, terrain)
    end

    # boosted_type : type renforcé de 50 %. classic_boost : le Champ classique
    # renforce déjà ce type pour les Pokémon au sol (x1,3).
    def register(id, name, terrain, boosted_type, classic_boost, description, order)
      BattleModifiers.register(id,
        name:        name,
        description: description,
        category:    :t_terrain,
        scope:       :global,
        exclusive:   :terrain,
        order:       order
      ) do |m|
        m.on(:on_battle_init) do |battle|
          BattleModifiers::Locks.lock_terrain(battle, terrain,
            strict:        true,
            tier:          2,
            block_message: _INTL("Mais le {1} ne peut pas être remplacé !", name))
        end
        m.on(:on_battle_start) do |battle|
          battle.pbDisplay(_INTL("C'est un {1} ! Il restera jusqu'à la fin du combat.", name))
        end
        # +50 % au total (le x1,3 du Champ classique est compris).
        m.on(:damage_multipliers) do |user, target, move, type, base_damage, multipliers|
          next if type != boosted_type || !active?(user.battle, terrain)
          factor = 1.5
          factor /= CLASSIC_BOOST if classic_boost && user.affectedByTerrain?
          multipliers[:power_multiplier] *= factor
        end
        yield m if block_given?
      end
    end
  end
end

#-------------------------------------------------------------------------------
# T-Électrique
#-------------------------------------------------------------------------------
BattleSimulator::TTerrains.register(:t_electric,
  _INTL("T-Électrique"), :Electric, :ELECTRIC, true,
  _INTL("Champ Électrifié verrouillé : attaques Électrik +50 %. Ni retirable ni remplaçable."), 10)

#-------------------------------------------------------------------------------
# T-Psy
#-------------------------------------------------------------------------------
BattleSimulator::TTerrains.register(:t_psychic,
  _INTL("T-Psy"), :Psychic, :PSYCHIC, true,
  _INTL("Champ Psychique verrouillé : attaques Psy +50 %. Ni retirable ni remplaçable."), 11)

#-------------------------------------------------------------------------------
# T-Herbu : soin de 1/8 par tour ; Séisme, Piétisol, Ampleur et Tunnel échouent.
#-------------------------------------------------------------------------------
BattleSimulator::TTerrains.register(:t_grassy,
  _INTL("T-Herbu"), :Grassy, :GRASS, true,
  _INTL("Champ Herbu verrouillé : Plante +50 %, soin de 1/8 PV par tour ; Séisme, Piétisol, Ampleur et Tunnel échouent."), 12
) do |m|
  failing_moves = [
    "DoublePowerIfTargetUnderground",            # Séisme
    "LowerTargetSpeed1WeakerInGrassyTerrain",    # Piétisol
    "RandomPowerDoublePowerIfTargetUnderground", # Ampleur
    "TwoTurnAttackInvulnerableUnderground"       # Tunnel
  ]
  m.on(:move_fails) do |user, move, targets, show_message|
    next false if !failing_moves.include?(move.function_code)
    next false if !BattleSimulator::TTerrains.active?(user.battle, :Grassy)
    if show_message
      user.battle.pbDisplay(_INTL("Mais le T-Herbu étouffe l'attaque {1} !", move.name))
    end
    next true
  end
  # Soin de fin de tour : 1/8 au lieu de 1/16, pour tous les Pokémon.
  m.on(:eor_terrain_healing) do |battle, battler|
    next nil if !BattleSimulator::TTerrains.active?(battle, :Grassy)
    next true if battler.fainted? || !battler.canHeal?
    battler.pbRecoverHP(battler.totalhp / 8)
    battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    next true
  end
  m.on(:ai_eor_damage) do |damage, battler|
    next nil if !BattleSimulator::TTerrains.active?(battler.battle, :Grassy)
    next nil if !battler.canHeal?
    # L'IA compte déjà 1/16 pour les Pokémon au sol.
    damage += [battler.totalhp / 16, 1].max if battler.affectedByTerrain?
    next damage - [battler.totalhp / 8, 1].max
  end
end

#-------------------------------------------------------------------------------
# T-Brume : Fée +50 % ; les attaques Dragon n'ont aucun effet.
#-------------------------------------------------------------------------------
BattleSimulator::TTerrains.register(:t_misty,
  _INTL("T-Brume"), :Misty, :FAIRY, false,
  _INTL("Champ Brumeux verrouillé : Fée +50 %, les attaques Dragon n'ont aucun effet. Ni retirable ni remplaçable."), 13
) do |m|
  m.on(:type_effectiveness) do |effectiveness, move, move_type, user, target|
    next nil if move_type != :DRAGON || !move.damagingMove?
    next nil if !BattleSimulator::TTerrains.active?(user.battle, :Misty)
    next Effectiveness::INEFFECTIVE_MULTIPLIER
  end
end

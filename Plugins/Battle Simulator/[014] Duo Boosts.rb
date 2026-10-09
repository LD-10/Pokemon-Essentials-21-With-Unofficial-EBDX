#===============================================================================
# Étape 6 - Boosts Duo (format Duo uniquement).
#
# Effets passifs et permanents de l'équipe IA, comme si un partenaire lançait
# l'attaque de soutien sur chaque Pokémon de l'IA à son entrée en jeu (début
# du combat, switch, remplacement après un K.O.). Ce sont de vrais
# changements de stats : l'IA en tient compte, Buée Noire et Bain de Smog les
# annulent jusqu'à la prochaine entrée en jeu, Contraire les inverse.
#
# Coup d'Main est différent : toutes les attaques de l'IA sont x1,5.
#===============================================================================
module BattleSimulator
  module DuoBoosts
    module_function

    # stats = { :ATTACK => 1, ... } ; condition = proc { |battler| ... } ou nil.
    def register(id, name, move, stats, description, order, condition = nil)
      BattleModifiers.register(id,
        name:        name,
        description: description,
        category:    :duo_boost,
        scope:       :ai_side,
        formats:     [:double],
        order:       order
      ) do |m|
        m.on(:on_battler_enter) do |battle, battler|
          next if !BattleModifiers.ai_battler?(battler)
          next if condition && !condition.call(battler)
          BattleModifiers::Tools.raise_stats(battler, stats, cause_name(move))
        end
      end
    end

    # Nom de l'attaque dans la langue du jeu (affiché dans le message de hausse).
    def cause_name(move)
      data = GameData::Move.try_get(move)
      return (data) ? data.name : move.to_s
    end
  end
end

#-------------------------------------------------------------------------------
# Cri Draconique : taux de critique +1 cran, +2 pour les Pokémon Dragon. Même
# effet que l'attaque du Gen 9 Pack (stocké comme Puissance, donc ne se cumule
# pas avec Puissance/Cri Draconique déjà actifs).
#-------------------------------------------------------------------------------
BattleModifiers.register(:duo_dragon_cheer,
  name:        _INTL("Cri Draconique"),
  description: _INTL("Taux de critique de l'IA +1 cran (+2 pour les Dragon), à chaque entrée en jeu."),
  category:    :duo_boost,
  scope:       :ai_side,
  formats:     [:double],
  order:       0
) do |m|
  m.on(:on_battler_enter) do |battle, battler|
    next if !BattleModifiers.ai_battler?(battler)
    next if battler.effects[PBEffects::FocusEnergy] > 0
    battler.effects[PBEffects::FocusEnergy] = (battler.pbHasType?(:DRAGON)) ? 2 : 1
    battle.pbCommonAnimation("StatUp", battler)
    battle.pbDisplay(_INTL("{1} is getting pumped!", battler.pbThis))
  end
end

BattleSimulator::DuoBoosts.register(:duo_coaching,
  _INTL("Coaching"), :COACHING, { :ATTACK => 1, :DEFENSE => 1 },
  _INTL("Attaque et Défense +1 pour chaque Pokémon de l'IA à son entrée en jeu."), 1)

BattleSimulator::DuoBoosts.register(:duo_aromatic_mist,
  _INTL("Brume Capiteuse"), :AROMATICMIST, { :SPECIAL_DEFENSE => 1 },
  _INTL("Défense Spéciale +1 pour chaque Pokémon de l'IA à son entrée en jeu."), 2)

BattleSimulator::DuoBoosts.register(:duo_decorate,
  _INTL("Nappage"), :DECORATE, { :ATTACK => 2, :SPECIAL_ATTACK => 2 },
  _INTL("Attaque et Attaque Spéciale +2 pour chaque Pokémon de l'IA à son entrée en jeu."), 3)

#-------------------------------------------------------------------------------
# Acupression : une stat au hasard +2 (parmi celles qui ne sont pas déjà à +6,
# précision et esquive comprises, comme l'attaque).
#-------------------------------------------------------------------------------
BattleModifiers.register(:duo_acupressure,
  name:        _INTL("Acupression"),
  description: _INTL("Une stat au hasard +2 (précision et esquive comprises) pour chaque Pokémon de l'IA à son entrée en jeu."),
  category:    :duo_boost,
  scope:       :ai_side,
  formats:     [:double],
  order:       4
) do |m|
  m.on(:on_battler_enter) do |battle, battler|
    next if !BattleModifiers.ai_battler?(battler)
    pool = []
    GameData::Stat.each_battle do |s|
      pool.push(s.id) if battler.stages[s.id] < Battle::Battler::STAT_STAGE_MAXIMUM
    end
    next if pool.empty?
    stat = pool[battle.pbRandom(pool.length)]
    BattleModifiers::Tools.raise_stats(battler, { stat => 2 },
                                       BattleSimulator::DuoBoosts.cause_name(:ACUPRESSURE))
  end
end

BattleSimulator::DuoBoosts.register(:duo_magnetic_flux,
  _INTL("Magné-Contrôle"), :MAGNETICFLUX, { :DEFENSE => 1, :SPECIAL_DEFENSE => 1 },
  _INTL("Défense et Défense Spéciale +1 pour chaque Pokémon de l'IA à son entrée en jeu (sans Plus/Minus)."), 5)

BattleSimulator::DuoBoosts.register(:duo_gear_up,
  _INTL("Engrenage"), :GEARUP, { :ATTACK => 1, :SPECIAL_ATTACK => 1 },
  _INTL("Attaque et Attaque Spéciale +1 pour chaque Pokémon de l'IA à son entrée en jeu (sans Plus/Minus)."), 6)

BattleSimulator::DuoBoosts.register(:duo_flower_shield,
  _INTL("Garde Florale"), :FLOWERSHIELD, { :DEFENSE => 1 },
  _INTL("Défense +1 pour chaque Pokémon Plante de l'IA à son entrée en jeu."), 7,
  proc { |battler| battler.pbHasType?(:GRASS) })

BattleSimulator::DuoBoosts.register(:duo_rototiller,
  _INTL("Fertilisation"), :ROTOTILLER, { :ATTACK => 1, :SPECIAL_ATTACK => 1 },
  _INTL("Attaque et Attaque Spéciale +1 pour chaque Pokémon Plante de l'IA à son entrée en jeu."), 8,
  proc { |battler| battler.pbHasType?(:GRASS) })

BattleSimulator::DuoBoosts.register(:duo_howl,
  _INTL("Grondement"), :HOWL, { :ATTACK => 1 },
  _INTL("Attaque +1 pour chaque Pokémon de l'IA à son entrée en jeu."), 9)

#-------------------------------------------------------------------------------
# Coup d'Main : toutes les attaques de l'IA sont x1,5 (comme si le partenaire
# lançait Coup d'Main à chaque tour). Se cumule avec un vrai Coup d'Main.
#-------------------------------------------------------------------------------
BattleModifiers.register(:duo_helping_hand,
  name:        _INTL("Coup d'Main"),
  description: _INTL("Puissance de toutes les attaques de l'IA x1,5, à chaque tour."),
  category:    :duo_boost,
  scope:       :ai_side,
  formats:     [:double],
  order:       10
) do |m|
  m.on(:damage_multipliers) do |user, target, move, type, base_damage, multipliers|
    next if !BattleModifiers.ai_battler?(user) || move.is_a?(Battle::Move::Confusion)
    multipliers[:power_multiplier] *= 1.5
  end
end

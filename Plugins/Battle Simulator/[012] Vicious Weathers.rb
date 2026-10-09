#===============================================================================
# Étape 4 - Vicious Weathers (météos de niveau 2).
#
# Une Vicious Weather est la vraie météo correspondante (tous ses effets
# habituels restent) avec des dégâts renforcés, et elle est verrouillée :
#   - elle est là dès le début et dure tout le combat ;
#   - les attaques et talents météo ordinaires (Danse Pluie, Crachin,
#     Sécheresse...) ne la remplacent pas ;
#   - seules les météos primales (Terre Finale, Mer Primaire, Souffle Delta)
#     la remplacent, tant que leur porteur reste sur le terrain : elle revient
#     dès qu'il part ou est K.O. ;
#   - Air Lock l'annule normalement, mais Ciel Gris n'a aucun effet sur elle.
#
# Les dégâts gardent les exceptions habituelles de la météo : Garde Magik,
# Envelocape, Lunettes Filtre, Pokémon sous terre (Tunnel)...
#===============================================================================
module BattleSimulator
  module ViciousWeathers
    module_function

    def active?(weather)
      lock = BattleModifiers::Locks.weather_lock
      return !lock.nil? && lock[:weather] == weather
    end

    # damage_check : le Pokémon subit-il les dégâts de 1/8 ?
    # base_check   : prend-il les dégâts normaux (1/16) comptés par l'IA ?
    def register(id, name, weather, description, damage_text, damage_check, base_check, order)
      BattleModifiers.register(id,
        name:        name,
        description: description,
        category:    :vicious,
        scope:       :global,
        exclusive:   :weather,
        order:       order
      ) do |m|
        m.on(:on_battle_init) do |battle|
          BattleModifiers::Locks.lock_weather(battle, weather,
            strict:             true,
            tier:               2,
            ignores_cloud_nine: true,
            block_message:      _INTL("Mais la {1} empêche la météo de changer !", name))
        end
        m.on(:on_battle_start) do |battle|
          battle.pbDisplay(_INTL("C'est une {1} ! Elle restera jusqu'à la fin du combat.", name))
        end
        # Ciel Gris affiche "les effets de la météo disparaissent" : on corrige.
        m.on(:on_battler_enter) do |battle, battler|
          next if !active?(weather) || battle.field.weather != weather
          next if !battler.hasActiveAbility?(:CLOUDNINE)
          next if battle.allBattlers.any? { |b| b.hasActiveAbility?(:AIRLOCK) }
          battle.pbDisplay(_INTL("Mais Ciel Gris n'a aucun effet sur la {1} !", name))
        end
        # 1/8 des PV max par tour au lieu de 1/16.
        m.on(:eor_weather_damage) do |battle, battler|
          next nil if !active?(weather)
          next true if battler.fainted?
          next nil if battler.effectiveWeather != weather   # Air Lock, météo primale...
          next true if !damage_check.call(battler)
          battle.pbDisplay(damage_text.call(battler))
          battle.scene.pbDamageAnimation(battler)
          battler.pbReduceHP(battler.totalhp / 8, false)
          battler.pbItemHPHealCheck
          battler.pbFaint if battler.fainted?
          next true
        end
        m.on(:ai_eor_damage) do |damage, battler|
          next nil if !active?(weather) || battler.effectiveWeather != weather
          damage -= [battler.totalhp / 16, 1].max if base_check.call(battler)
          damage += [battler.totalhp / 8, 1].max if damage_check.call(battler)
          next damage
        end
        yield m if block_given?
      end
    end

    def underground_or_underwater?(battler)
      return battler.inTwoTurnAttack?("TwoTurnAttackInvulnerableUnderground",
                                      "TwoTurnAttackInvulnerableUnderwater")
    end

    # Exceptions de la grêle, indépendantes de HAIL_WEATHER_TYPE (en mode Neige,
    # takesHailDamage? renvoie toujours false).
    def takes_vicious_hail_damage?(battler)
      return false if !battler.takesIndirectDamage?
      return false if battler.pbHasType?(:ICE)
      return false if underground_or_underwater?(battler)
      return false if battler.hasActiveAbility?([:OVERCOAT, :ICEBODY, :SNOWCLOAK])
      return false if battler.hasActiveItem?(:SAFETYGOGGLES)
      return true
    end
  end
end

#-------------------------------------------------------------------------------
# Vicious Sandstorm : 1/8 PV par tour (sauf Roche/Sol/Acier) ; Déf. Spé. x1,5
# pour les types Roche ET Sol.
#-------------------------------------------------------------------------------
BattleSimulator::ViciousWeathers.register(:vicious_sandstorm,
  _INTL("Vicious Sandstorm"), :Sandstorm,
  _INTL("Tempête de sable verrouillée : 1/8 PV par tour (sauf Roche/Sol/Acier), Déf. Spé. x1,5 pour Roche et Sol. Ciel Gris sans effet."),
  proc { |battler| _INTL("{1} is buffeted by the sandstorm!", battler.pbThis) },
  proc { |battler| battler.takesSandstormDamage? },
  proc { |battler| battler.takesSandstormDamage? },
  10
) do |m|
  # Le jeu donne déjà x1,5 aux types Roche : on l'ajoute aux types Sol (une
  # seule fois pour un Pokémon Roche/Sol).
  m.on(:damage_multipliers) do |user, target, move, type, base_damage, multipliers|
    next if !BattleSimulator::ViciousWeathers.active?(:Sandstorm)
    next if !target.pbHasType?(:GROUND) || target.pbHasType?(:ROCK)
    next if user.effectiveWeather != :Sandstorm
    next if !move.specialMove?(type) || move.function_code == "UseTargetDefenseInsteadOfTargetSpDef"
    multipliers[:defense_multiplier] *= 1.5
  end
end

#-------------------------------------------------------------------------------
# Vicious Hail : 1/8 PV par tour (sauf Glace).
#-------------------------------------------------------------------------------
BattleSimulator::ViciousWeathers.register(:vicious_hail,
  _INTL("Vicious Hail"), :Hail,
  _INTL("Grêle verrouillée : 1/8 PV par tour (sauf Glace). Défense des types Glace x1,5 (mode Grêle + Neige). Ciel Gris sans effet."),
  proc { |battler| _INTL("{1} is buffeted by the hail!", battler.pbThis) },
  proc { |battler| BattleSimulator::ViciousWeathers.takes_vicious_hail_damage?(battler) },
  proc { |battler| battler.takesHailDamage? },
  11
)

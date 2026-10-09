#===============================================================================
# Gimmicks de démonstration (étape 1).
#
# Ils ne servent qu'à vérifier que le moteur BattleModifiers et ses hooks
# fonctionnent en jeu. Ils sont masqués du menu quand
# BattleSimulator::SHOW_DEMO_MODIFIERS = false, et ce fichier pourra être
# supprimé une fois les vrais gimmicks en place.
#===============================================================================

# Événements du cycle de vie : un message à chaque étape.
BattleModifiers.register(:demo_event_log,
  name:        _INTL("Démo : journal des événements"),
  description: _INTL("Affiche un message au début du combat, à chaque entrée en jeu et à chaque fin de tour (test des hooks)."),
  category:    :demo,
  scope:       :global,
  order:       -100
) do |m|
  m.on(:on_battle_start) do |battle|
    battle.pbDisplay(_INTL("[Démo] Le combat commence."))
  end
  m.on(:on_battler_enter) do |battle, battler|
    battle.pbDisplay(_INTL("[Démo] {1} entre en jeu.", battler.pbThis))
  end
  m.on(:on_end_of_round) do |battle|
    battle.pbDisplay(_INTL("[Démo] Fin du tour {1}.", battle.turnCount + 1))
  end
end

# Hook de dégâts (Battle::Move#pbCalcDamageMultipliers).
BattleModifiers.register(:demo_player_power,
  name:        _INTL("Démo : attaques du joueur x1,5"),
  description: _INTL("La puissance des attaques des Pokémon du joueur est multipliée par 1,5 (test du hook de dégâts)."),
  category:    :demo,
  scope:       :player_side
) do |m|
  m.on(:damage_multipliers) do |user, target, move, type, base_damage, multipliers|
    multipliers[:power_multiplier] *= 1.5 if BattleModifiers.player_battler?(user)
  end
end

# Hook de vitesse (Battle::Battler#pbSpeed).
BattleModifiers.register(:demo_ai_speed,
  name:        _INTL("Démo : Vitesse x2 pour l'IA"),
  description: _INTL("La Vitesse des Pokémon de l'IA est doublée (test du hook de vitesse)."),
  category:    :demo,
  scope:       :ai_side
) do |m|
  m.on(:speed) do |speed, battler|
    next speed * 2 if BattleModifiers.ai_battler?(battler)
  end
end

# Talents virtuels : Lévitation passe par hasActiveAbility? (airborne?), Torche
# par les handlers de Battle::AbilityEffects (MoveImmunity, DamageCalcFromUser).
BattleModifiers.register(:demo_ai_abilities,
  name:        _INTL("Démo : Lévitation + Torche pour l'IA"),
  description: _INTL("Les Pokémon de l'IA ont Lévitation et Torche en plus de leur talent (test des talents virtuels)."),
  category:    :demo,
  scope:       :ai_side
) do |m|
  m.on(:extra_abilities) do |battler|
    next [:LEVITATE, :FLASHFIRE] if BattleModifiers.ai_battler?(battler)
  end
end

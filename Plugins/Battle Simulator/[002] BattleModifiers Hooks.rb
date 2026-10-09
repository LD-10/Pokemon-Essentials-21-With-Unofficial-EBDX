#===============================================================================
# BattleModifiers - hooks non destructifs.
#
# Chaque méthode est enveloppée par un alias (comme le font l'EBDX et le Gen 9
# Pack) : la méthode d'origine est toujours appelée, BattleModifiers ne fait que
# lire ou ajuster son résultat. Ce plugin est chargé après l'EBDX et le Gen 9
# Pack (voir meta.txt), donc ce sont leurs versions qui sont enveloppées.
#
# Hors d'un combat du simulateur, BattleModifiers.active? est faux et chaque
# hook renvoie directement le résultat d'origine.
#===============================================================================

#===============================================================================
# Battle : cycle de vie, météo, terrain.
#===============================================================================
class Battle
  alias __bmod_pbStartBattle pbStartBattle unless method_defined?(:__bmod_pbStartBattle)
  def pbStartBattle
    BattleModifiers.attach_battle(self)
    begin
      BattleModifiers.trigger(:on_battle_init, self)
      return __bmod_pbStartBattle
    ensure
      BattleModifiers.detach_battle(self)
    end
  end

  alias __bmod_pbOnAllBattlersEnteringBattle pbOnAllBattlersEnteringBattle unless method_defined?(:__bmod_pbOnAllBattlersEnteringBattle)
  def pbOnAllBattlersEnteringBattle
    BattleModifiers.trigger(:on_battle_start, self)
    return __bmod_pbOnAllBattlersEnteringBattle
  end

  alias __bmod_pbOnBattlerEnteringBattle pbOnBattlerEnteringBattle unless method_defined?(:__bmod_pbOnBattlerEnteringBattle)
  def pbOnBattlerEnteringBattle(battler_index, skip_event_reset = false)
    indices = [battler_index].flatten
    ret = __bmod_pbOnBattlerEnteringBattle(battler_index, skip_event_reset)
    if BattleModifiers.active?
      entered = indices.map { |i| @battlers[i] }.compact.reject { |b| b.fainted? }
      entered.sort_by { |b| -b.pbSpeed }.each do |b|
        next if b.fainted?
        BattleModifiers.trigger(:on_battler_enter, self, b)
      end
    end
    return ret
  end

  alias __bmod_pbEndOfRoundPhase pbEndOfRoundPhase unless method_defined?(:__bmod_pbEndOfRoundPhase)
  def pbEndOfRoundPhase
    BattleModifiers.trigger(:before_end_of_round, self)
    ret = __bmod_pbEndOfRoundPhase
    BattleModifiers.trigger(:on_end_of_round, self) if @decision == 0
    return ret
  end

  alias __bmod_pbEndOfBattle pbEndOfBattle unless method_defined?(:__bmod_pbEndOfBattle)
  def pbEndOfBattle
    ret = __bmod_pbEndOfBattle
    BattleModifiers.trigger(:on_battle_end, self, @decision)
    return ret
  end

  alias __bmod_pbWeather pbWeather unless method_defined?(:__bmod_pbWeather)
  def pbWeather
    ret = __bmod_pbWeather
    return ret if !BattleModifiers.active?
    return BattleModifiers.modify(:effective_weather, ret, self)
  end

  alias __bmod_pbStartWeather pbStartWeather unless method_defined?(:__bmod_pbStartWeather)
  def pbStartWeather(user, newWeather, fixedDuration = false, showAnim = true)
    if @field.weather != newWeather &&
       !BattleModifiers.allow?(:can_change_weather, self, user, newWeather)
      # pbStartWeatherAbility affiche la bulle de talent avant d'appeler cette
      # méthode, qui est censée la cacher.
      pbHideAbilitySplash(user) if user
      return
    end
    return __bmod_pbStartWeather(user, newWeather, fixedDuration, showAnim)
  end

  alias __bmod_pbStartTerrain pbStartTerrain unless method_defined?(:__bmod_pbStartTerrain)
  def pbStartTerrain(user, newTerrain, fixedDuration = true)
    if @field.terrain != newTerrain &&
       !BattleModifiers.allow?(:can_change_terrain, self, user, newTerrain)
      pbHideAbilitySplash(user) if user
      return
    end
    return __bmod_pbStartTerrain(user, newTerrain, fixedDuration)
  end

  alias __bmod_pbEORWeatherDamage pbEORWeatherDamage unless method_defined?(:__bmod_pbEORWeatherDamage)
  def pbEORWeatherDamage(battler)
    return if BattleModifiers.override(:eor_weather_damage, self, battler)
    return __bmod_pbEORWeatherDamage(battler)
  end

  alias __bmod_pbEORTerrainHealing pbEORTerrainHealing unless method_defined?(:__bmod_pbEORTerrainHealing)
  def pbEORTerrainHealing(battler)
    return if BattleModifiers.override(:eor_terrain_healing, self, battler)
    return __bmod_pbEORTerrainHealing(battler)
  end

  # Quand un talent virtuel vient d'être reconnu par hasActiveAbility?, la bulle
  # de talent affiche son nom au lieu de celui du talent réel.
  alias __bmod_pbShowAbilitySplash pbShowAbilitySplash unless method_defined?(:__bmod_pbShowAbilitySplash)
  def pbShowAbilitySplash(battler, *args)
    shown = (battler && BattleModifiers.active?) ? battler.bmod_shown_ability : nil
    if !shown || shown == battler.ability_id
      return __bmod_pbShowAbilitySplash(battler, *args)
    end
    return battler.bmod_with_ability(shown) { __bmod_pbShowAbilitySplash(battler, *args) }
  end
end

#===============================================================================
# Battle::Battler : talents (y compris virtuels), vitesse, statuts, stats.
#===============================================================================
class Battle::Battler
  # Talent virtuel reconnu en dernier par hasActiveAbility? (pour la bulle).
  attr_reader :bmod_shown_ability

  # Talents virtuels de ce Pokémon, sans son talent actuel. Pendant l'exécution
  # du handler d'un talent virtuel, @ability_id vaut temporairement ce talent et
  # le talent réel est alors compté parmi les talents "en plus".
  def bmod_extra_abilities
    ret = BattleModifiers.extra_abilities_for(self)
    ret.push(@bmod_real_ability) if @bmod_real_ability
    ret.delete(@ability_id)
    return ret
  end

  # Exécute le bloc comme si le Pokémon avait le talent ability_id (utilisé pour
  # les handlers des talents virtuels et pour la bulle de talent).
  def bmod_with_ability(ability_id)
    old_ability = @ability_id
    old_real    = @bmod_real_ability
    @bmod_real_ability ||= old_ability
    @bmod_shown_ability = nil
    @ability_id = ability_id
    begin
      return yield
    ensure
      if @ability_id == ability_id
        @ability_id        = old_ability
        @bmod_real_ability = old_real
      else
        # Le handler a réellement changé le talent (Calque...) : on le garde.
        @bmod_real_ability = nil
      end
    end
  end

  def bmod_clear_shown_ability
    @bmod_shown_ability = nil
  end

  alias __bmod_hasActiveAbility? hasActiveAbility? unless method_defined?(:__bmod_hasActiveAbility?)
  def hasActiveAbility?(check_ability, ignore_fainted = false)
    if __bmod_hasActiveAbility?(check_ability, ignore_fainted)
      @bmod_shown_ability = nil if @bmod_shown_ability
      return true
    end
    return false if !BattleModifiers.active?
    extras = bmod_extra_abilities
    return false if extras.empty?
    return false if !abilityActive?(ignore_fainted, check_ability)
    Array(check_ability).each do |abil|
      abil_id = (abil.is_a?(Symbol)) ? abil : GameData::Ability.try_get(abil)&.id
      next if !abil_id || !extras.include?(abil_id)
      @bmod_shown_ability = abil_id
      return true
    end
    return false
  end
  # Ces alias pointaient sur l'ancienne méthode : on les refait.
  alias hasWorkingAbility hasActiveAbility?

  alias __bmod_pbSpeed pbSpeed unless method_defined?(:__bmod_pbSpeed)
  def pbSpeed
    ret = __bmod_pbSpeed
    return ret if !BattleModifiers.active? || fainted?
    return [BattleModifiers.modify(:speed, ret, self).round, 1].max
  end

  alias __bmod_pbCanInflictStatus? pbCanInflictStatus? unless method_defined?(:__bmod_pbCanInflictStatus?)
  def pbCanInflictStatus?(newStatus, user, showMessages, move = nil, ignoreStatus = false)
    ret = __bmod_pbCanInflictStatus?(newStatus, user, showMessages, move, ignoreStatus)
    return ret if !ret || !BattleModifiers.active?
    return BattleModifiers.allow?(:can_inflict_status, self, newStatus, user, move, showMessages)
  end

  # Signature : (stat, user, move, showFailMsg, ignoreContrary, ignoreMirrorArmor)
  alias __bmod_pbCanLowerStatStage? pbCanLowerStatStage? unless method_defined?(:__bmod_pbCanLowerStatStage?)
  def pbCanLowerStatStage?(*args)
    ret = __bmod_pbCanLowerStatStage?(*args)
    return ret if !ret || !BattleModifiers.active?
    return BattleModifiers.allow?(:can_lower_stat, self, args[0], args[1], args[2], args[3] || false)
  end

  alias __bmod_pbUseMove pbUseMove unless method_defined?(:__bmod_pbUseMove)
  def pbUseMove(choice, specialUsage = false)
    ret = __bmod_pbUseMove(choice, specialUsage)
    BattleModifiers.trigger(:after_move_used, @battle, self, choice[2]) if BattleModifiers.active?
    return ret
  end
end

#===============================================================================
# Battle::Move : hooks posés sur chaque instance.
#
# Beaucoup de sous-classes d'attaques redéfinissent pbBaseDamage, pbMoveFailed?,
# pbPriority... sans appeler super : un alias sur Battle::Move ne les verrait
# pas. On étend donc chaque instance avec ce module (extend), qui passe avant la
# classe de l'attaque dans la recherche de méthodes : "super" appelle la vraie
# implémentation (sous-classe, Gen 9 Pack...) et le hook ajuste son résultat.
#===============================================================================
module BattleModifiers
  module MoveHooks
    def pbPriority(user)
      ret = super
      return ret if !BattleModifiers.active?
      return BattleModifiers.modify(:move_priority, ret, user, self)
    end

    def pbMoveFailed?(user, targets)
      return true if super
      return BattleModifiers.any?(:move_fails, user, self, targets)
    end

    def pbFailsAgainstTarget?(user, target, show_message)
      return true if super
      return BattleModifiers.any?(:move_fails_against, user, target, self, show_message)
    end

    def pbCalcTypeMod(moveType, user, target)
      ret = super
      return ret if !BattleModifiers.active?
      return BattleModifiers.modify(:type_effectiveness, ret, self, moveType, user, target)
    end

    def pbBaseDamage(baseDmg, user, target)
      ret = super
      return ret if !BattleModifiers.active?
      return BattleModifiers.modify(:base_damage, ret, user, target, self)
    end

    def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
      ret = super
      BattleModifiers.trigger(:damage_multipliers, user, target, self, type, baseDmg, multipliers)
      return ret
    end

    def pbCalcAccuracyModifiers(user, target, modifiers)
      ret = super
      BattleModifiers.trigger(:accuracy_modifiers, user, target, self, modifiers)
      return ret
    end

    # Les crans de critique en plus passent par l'effet Puissance (FocusEnergy),
    # que pbIsCritical? additionne déjà au taux de critique.
    def pbIsCritical?(user, target)
      bonus = BattleModifiers.modify(:critical_stage_bonus, 0, user, target, self)
      return super if !bonus.is_a?(Integer) || bonus == 0
      user.effects[PBEffects::FocusEnergy] += bonus
      begin
        return super
      ensure
        user.effects[PBEffects::FocusEnergy] -= bonus
      end
    end
  end
end

class Battle::Move
  class << self
    alias __bmod_new new unless method_defined?(:__bmod_new)
    # Toutes les créations d'attaques (from_pokemon_move, Lutte, confusion...)
    # passent par new, y compris pour les sous-classes.
    def new(*args, &block)
      move = __bmod_new(*args, &block)
      move.extend(BattleModifiers::MoveHooks) if BattleModifiers.session
      return move
    end
  end
end

#===============================================================================
# Battle::AbilityEffects : exécute aussi les handlers des talents virtuels.
#
# Quand le jeu déclenche un handler de talent (ex. triggerDamageCalcFromTarget
# pour le talent de la cible), on retrouve le Pokémon qui porte ce talent, puis
# on exécute aussi le handler de chacun de ses talents virtuels, en combinant
# les résultats selon le type de handler.
#===============================================================================
module BattleModifiers
  module AbilityMultiplexer
    # Nom du handler => [porteur, mode, index de la valeur]
    #   porteur : index (dans les arguments qui suivent le talent) du Pokémon
    #             qui porte le talent, ou [:ally, i] si le talent appartient à un
    #             allié de l'argument i.
    #   mode    : :each  -> tous les handlers sont exécutés
    #             :or    -> on s'arrête au premier qui renvoie true
    #             :chain -> la valeur à "index" est passée d'un handler à l'autre
    #             :first -> 1re valeur différente de 0 (PriorityBracketChange)
    SPECS = {
      :SpeedCalc                        => [0, :chain, 1],
      :WeightCalc                       => [0, :chain, 1],
      :OnHPDroppedBelowHalf             => [0, :or],
      :StatusCheckNonIgnorable          => [0, :or],
      :StatusImmunity                   => [0, :or],
      :StatusImmunityNonIgnorable       => [0, :or],
      :StatusImmunityFromAlly           => [[:ally, 0], :or],
      :OnStatusInflicted                => [0, :each],
      :StatusCure                       => [0, :each],
      :StatLossImmunity                 => [0, :or],
      :StatLossImmunityNonIgnorable     => [0, :or],
      :StatLossImmunityFromAlly         => [0, :or],
      :OnStatGain                       => [0, :each],
      :OnStatLoss                       => [0, :each],
      :PriorityChange                   => [0, :chain, 2],
      :PriorityBracketChange            => [0, :first],
      :PriorityBracketUse               => [0, :each],
      :OnFlinch                         => [0, :each],
      :MoveBlocking                     => [0, :or],
      :MoveImmunity                     => [1, :or],
      :ModifyMoveBaseType               => [0, :chain, 2],
      :AccuracyCalcFromUser             => [1, :each],
      :AccuracyCalcFromAlly             => [[:ally, 1], :each],
      :AccuracyCalcFromTarget           => [2, :each],
      :DamageCalcFromUser               => [0, :each],
      :DamageCalcFromAlly               => [[:ally, 0], :each],
      :DamageCalcFromTarget             => [1, :each],
      :DamageCalcFromTargetNonIgnorable => [1, :each],
      :DamageCalcFromTargetAlly         => [[:ally, 1], :each],
      :CriticalCalcFromUser             => [0, :chain, 2],
      :CriticalCalcFromTarget           => [1, :chain, 2],
      :OnBeingHit                       => [1, :each],
      :OnDealingHit                     => [0, :each],
      :OnEndOfUsingMove                 => [0, :each],
      :AfterMoveUseFromTarget           => [0, :each],
      :EndOfRoundWeather                => [1, :each],
      :EndOfRoundHealing                => [0, :each],
      :EndOfRoundEffect                 => [0, :each],
      :EndOfRoundGainItem               => [0, :each],
      :CertainSwitching                 => [0, :or],
      :TrappingByTarget                 => [1, :or],
      :OnSwitchIn                       => [0, :each],
      :OnSwitchOut                      => [0, :each],
      :ChangeOnBattlerFainting          => [0, :each],
      :OnBattlerFainting                => [0, :each],
      :OnTerrainChange                  => [0, :each],
      :OnIntimidated                    => [0, :each],
      :CertainEscapeFromBattle          => [0, :or],
      # Ajoutés par le Generation 9 Pack
      :OnTypeChange                     => [0, :each],
      :OnOpposingStatGain               => [0, :each],
      :ModifyTypeEffectiveness          => [1, :chain, 4],
      :OnMoveSuccessCheck               => [1, :each]
    }

    module_function

    # Après un F12 (reset), mkxp-z réexécute tous les scripts : les méthodes
    # trigger* du jeu de base sont redéfinies par-dessus nos versions. On ne se
    # fie donc pas à l'existence de l'alias mais à la méthode actuellement en
    # place, et le HandlerHash est relu à chaque appel (il est recréé aussi).
    def install
      effects  = Battle::AbilityEffects
      wrappers = effects.instance_variable_get(:@__bmod_wrappers) || {}
      SPECS.each do |name, spec|
        trigger_method = "trigger#{name}".to_sym
        next if !effects.const_defined?(name) || !effects.respond_to?(trigger_method)
        next if wrappers[trigger_method] && effects.method(trigger_method) == wrappers[trigger_method]
        original = "__bmod_#{trigger_method}".to_sym
        effects.singleton_class.send(:alias_method, original, trigger_method)
        effects.define_singleton_method(trigger_method) do |ability, *args|
          ret = effects.send(original, ability, *args)
          next ret if !BattleModifiers.handles?(:extra_abilities)
          next AbilityMultiplexer.run_extras(effects.const_get(name), spec, ability, args, ret)
        end
        wrappers[trigger_method] = effects.method(trigger_method)
      end
      effects.instance_variable_set(:@__bmod_wrappers, wrappers)
    end

    # Pokémon qui porte le talent "ability" pour cet appel, ou nil.
    def owner_of(spec_owner, ability, args)
      ability_id = (ability.is_a?(Symbol)) ? ability : ability&.id
      return nil if !ability_id
      if spec_owner.is_a?(Array)
        ref = args[spec_owner[1]]
        return nil if !ref.is_a?(Battle::Battler)
        return ref.allAllies.find { |b| b.ability_id == ability_id }
      end
      battler = args[spec_owner]
      return nil if !battler.is_a?(Battle::Battler) || battler.ability_id != ability_id
      return battler
    end

    def run_extras(hash, spec, ability, args, ret)
      mode  = spec[1]
      index = spec[2]
      return ret if mode == :or && ret
      return ret if mode == :first && ret && ret != 0
      owner = owner_of(spec[0], ability, args)
      return ret if !owner
      owner.bmod_clear_shown_ability
      extras = owner.bmod_extra_abilities
      return ret if extras.empty?
      extras.each do |extra|
        call_args = args.clone
        call_args[index] = ret if mode == :chain
        value = owner.bmod_with_ability(extra) { hash.trigger(extra, *call_args) }
        case mode
        when :chain
          ret = value if !value.nil?
        when :or
          return value if value
        when :first
          return value if value && value != 0
        else   # :each
          ret ||= value
        end
      end
      return ret
    end
  end
end

BattleModifiers::AbilityMultiplexer.install

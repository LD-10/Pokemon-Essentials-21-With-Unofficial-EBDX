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
    return __bmod_pbOnBattlerEnteringBattle(battler_index, skip_event_reset) if !BattleModifiers.active?
    # Pokémon qui entrent maintenant. Le jeu peut en faire repartir un pendant
    # l'appel (Sac Éjection, Repli Tactique) : l'appel imbriqué du remplaçant
    # déclenche déjà ses propres événements d'entrée.
    entering = indices.map { |i| [i, @battlers[i]&.pokemon] }
    indices.each do |i|
      next if !@battlers[i]
      @battlers[i].bmod_clear_shown_ability
      @battlers[i].bmod_entry_pending = true
    end
    begin
      ret = __bmod_pbOnBattlerEnteringBattle(battler_index, skip_event_reset)
    ensure
      indices.each { |i| @battlers[i]&.bmod_entry_pending = false }
    end
    if BattleModifiers.active?
      entered = entering.map do |i, pkmn|
        b = @battlers[i]
        (b && pkmn && b.pokemon.equal?(pkmn) && !b.fainted?) ? b : nil
      end
      entered.compact.sort_by { |b| -b.pbSpeed }.each do |b|
        next if b.fainted?
        BattleModifiers.trigger(:on_battler_enter, self, b)
      end
      BattleModifiers::Locks.reconcile(self, :enter)
    end
    return ret
  end

  alias __bmod_pbEndOfRoundPhase pbEndOfRoundPhase unless method_defined?(:__bmod_pbEndOfRoundPhase)
  def pbEndOfRoundPhase
    BattleModifiers.trigger(:before_end_of_round, self)
    ret = __bmod_pbEndOfRoundPhase
    if @decision == 0 && BattleModifiers.active?
      BattleModifiers.trigger(:on_end_of_round, self)
      BattleModifiers::Locks.reconcile(self, :round)
    end
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
    ret = BattleModifiers::Locks.effective_weather(self, ret)
    return BattleModifiers.modify(:effective_weather, ret, self)
  end

  alias __bmod_pbStartWeather pbStartWeather unless method_defined?(:__bmod_pbStartWeather)
  def pbStartWeather(user, newWeather, fixedDuration = false, showAnim = true)
    if !BattleModifiers.active?
      return __bmod_pbStartWeather(user, newWeather, fixedDuration, showAnim)
    end
    old_weather = @field.weather
    if old_weather != newWeather
      allowed = BattleModifiers::Locks.weather_change_allowed?(newWeather)
      # Talent (Crachin...) : on explique pourquoi la météo ne change pas.
      BattleModifiers::Locks.show_block_message(self, :weather) if !allowed && user
      allowed &&= BattleModifiers.allow?(:can_change_weather, self, user, newWeather)
      if !allowed
        # pbStartWeatherAbility affiche la bulle de talent avant d'appeler
        # cette méthode, qui est censée la cacher.
        pbHideAbilitySplash(user) if user
        return
      end
    end
    ret = __bmod_pbStartWeather(user, newWeather, fixedDuration, showAnim)
    if @field.weather != old_weather
      BattleModifiers.trigger(:on_weather_change, self, old_weather, @field.weather)
    end
    return ret
  end

  alias __bmod_pbStartTerrain pbStartTerrain unless method_defined?(:__bmod_pbStartTerrain)
  def pbStartTerrain(user, newTerrain, fixedDuration = true)
    if BattleModifiers.active? && @field.terrain != newTerrain
      allowed = BattleModifiers::Locks.terrain_change_allowed?(newTerrain)
      BattleModifiers::Locks.show_block_message(self, :terrain) if !allowed && user
      allowed &&= BattleModifiers.allow?(:can_change_terrain, self, user, newTerrain)
      if !allowed
        pbHideAbilitySplash(user) if user
        return
      end
    end
    return __bmod_pbStartTerrain(user, newTerrain, fixedDuration)
  end

  # Météo primale permanente (defaultWeather = :HarshSun...) : sans le plugin
  # "v21.1 Hotfixes", pbEndPrimordialWeather la retirerait puis la relancerait
  # (defaultWeather) à l'infini.
  alias __bmod_pbEndPrimordialWeather pbEndPrimordialWeather unless method_defined?(:__bmod_pbEndPrimordialWeather)
  def pbEndPrimordialWeather
    if BattleModifiers.active? && @field.weather == @field.defaultWeather &&
       BattleModifiers::Locks.weather_lock
      return
    end
    return __bmod_pbEndPrimordialWeather
  end

  # Les effets rendus permanents (BattleModifiers::Locks) ne décomptent pas.
  alias __bmod_pbEORCountDownSideEffect pbEORCountDownSideEffect unless method_defined?(:__bmod_pbEORCountDownSideEffect)
  def pbEORCountDownSideEffect(side, effect, msg)
    return if BattleModifiers.active? && @sides[side].effects[effect] > 0 &&
              BattleModifiers::Locks.side_locked?(side, effect)
    return __bmod_pbEORCountDownSideEffect(side, effect, msg)
  end

  alias __bmod_pbEORCountDownFieldEffect pbEORCountDownFieldEffect unless method_defined?(:__bmod_pbEORCountDownFieldEffect)
  def pbEORCountDownFieldEffect(effect, msg)
    return if BattleModifiers.active? && @field.effects[effect] > 0 &&
              BattleModifiers::Locks.field_locked?(effect)
    return __bmod_pbEORCountDownFieldEffect(effect, msg)
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
  # de talent affiche son nom au lieu de celui du talent réel. La valeur est
  # consommée par l'affichage.
  alias __bmod_pbShowAbilitySplash pbShowAbilitySplash unless method_defined?(:__bmod_pbShowAbilitySplash)
  def pbShowAbilitySplash(battler, *args)
    shown = (battler && BattleModifiers.active?) ? battler.bmod_shown_ability : nil
    if !shown || shown == battler.ability_id
      return __bmod_pbShowAbilitySplash(battler, *args)
    end
    battler.bmod_clear_shown_ability
    return battler.bmod_with_ability(shown) { __bmod_pbShowAbilitySplash(battler, *args) }
  end
end

#===============================================================================
# Battle::Battler : talents (y compris virtuels), vitesse, statuts, stats.
#===============================================================================
class Battle::Battler
  # Talent virtuel reconnu en dernier par hasActiveAbility? (pour la bulle).
  attr_reader :bmod_shown_ability
  # Vrai pendant une vraie entrée en jeu (talents virtuels OnSwitchIn).
  attr_accessor :bmod_entry_pending

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
    old_shown   = @bmod_shown_ability
    @bmod_real_ability ||= old_ability
    @bmod_shown_ability = nil
    @ability_id = ability_id
    begin
      return yield
    ensure
      @bmod_shown_ability = old_shown
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

  # La prochaine bulle de talent de ce Pokémon affichera ce talent virtuel.
  def bmod_show_ability(ability_id)
    @bmod_shown_ability = ability_id
  end

  # Neutralisation (ex. Gaz Inhibiteur de l'IA) : après le test d'origine.
  alias __bmod_abilityActive? abilityActive? unless method_defined?(:__bmod_abilityActive?)
  def abilityActive?(ignore_fainted = false, check_ability = nil)
    ret = __bmod_abilityActive?(ignore_fainted, check_ability)
    return ret if !ret || !BattleModifiers.handles?(:ability_active)
    return BattleModifiers.allow?(:ability_active, self, check_ability)
  end

  alias __bmod_hasActiveAbility? hasActiveAbility? unless method_defined?(:__bmod_hasActiveAbility?)
  def hasActiveAbility?(check_ability, ignore_fainted = false)
    if __bmod_hasActiveAbility?(check_ability, ignore_fainted)
      @bmod_shown_ability = nil if @bmod_shown_ability
      return true
    end
    return false if !BattleModifiers.extra_abilities?
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
    # Brume permanente stricte masquée pendant Anti-Brume : elle protège quand
    # même de la baisse d'Esquive.
    ret = BattleModifiers::Locks.with_hidden_side_effect(@battle, idxOwnSide, PBEffects::Mist) do
      __bmod_pbCanLowerStatStage?(*args)
    end
    return ret if !ret || !BattleModifiers.active?
    return BattleModifiers.allow?(:can_lower_stat, self, args[0], args[1], args[2], args[3] || false)
  end

  # Les talents à changement de forme (Banc, Mode Transe, Bouclier-Carcan...)
  # affichent la bulle du vrai talent : oublier un nom de talent virtuel retenu
  # par un test silencieux (ex. airborne? -> Lévitation pendant les picots).
  alias __bmod_pbCheckForm pbCheckForm unless method_defined?(:__bmod_pbCheckForm)
  def pbCheckForm(*args)
    bmod_clear_shown_ability if BattleModifiers.active?
    return __bmod_pbCheckForm(*args)
  end

  alias __bmod_pbUseMove pbUseMove unless method_defined?(:__bmod_pbUseMove)
  def pbUseMove(choice, specialUsage = false)
    return __bmod_pbUseMove(choice, specialUsage) if !BattleModifiers.active?
    # Oublie les noms de talents virtuels retenus pendant les calculs de l'IA.
    @battle.allBattlers.each { |b| b.bmod_clear_shown_ability }
    ret = __bmod_pbUseMove(choice, specialUsage)
    if BattleModifiers.active?
      BattleModifiers.trigger(:after_move_used, @battle, self, choice[2])
      BattleModifiers::Locks.reconcile(@battle, :move)
    end
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
      # Change Côté décide d'échouer selon les effets présents : il ne doit pas
      # voir les effets permanents stricts, comme pendant son effet.
      failed = if is_a?(Battle::Move::SwapSideEffects) && bmod_masks_removal?
                 BattleModifiers::Locks.hide_protected(@battle) { super(user, targets) }
               else
                 super(user, targets)
               end
      return true if failed
      return false if !BattleModifiers.active?
      return true if BattleModifiers::Locks.move_blocked?(@battle, self, true)
      return BattleModifiers.any?(:move_fails, user, self, targets, true)
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
      @bmod_strict_screen = bmod_strict_screen_against?(target)
      begin
        ret = super
      ensure
        @bmod_strict_screen = false
      end
      BattleModifiers.trigger(:damage_multipliers, user, target, self, type, baseDmg, multipliers)
      return ret
    end

    # Casse-Brique, Psycho-Croc, Rage Taurine ignorent les écrans parce qu'ils
    # les brisent. Un écran permanent strict n'est pas brisé : il réduit aussi
    # ce coup.
    def ignoresReflect?
      return false if @bmod_strict_screen
      return super
    end

    def bmod_strict_screen_against?(target)
      return false if !BattleModifiers.active? || !is_a?(Battle::Move::RemoveScreens)
      locks = BattleModifiers::Locks.state[:side_locks]
      return false if !locks
      side    = target.idxOwnSide
      effects = target.pbOwnSide.effects
      strict  = lambda { |e| locks[[side, e]] == true && effects[e] > 0 }
      return true if strict.call(PBEffects::AuroraVeil)
      return true if physicalMove? && strict.call(PBEffects::Reflect)
      return true if specialMove? && strict.call(PBEffects::LightScreen)
      return false
    end

    def pbCalcAccuracyModifiers(user, target, modifiers)
      ret = super
      BattleModifiers.trigger(:accuracy_modifiers, user, target, self, modifiers)
      return ret
    end

    def pbCheckDamageAbsorption(user, target)
      ret = super
      BattleModifiers.trigger(:damage_absorption, user, target, self) if BattleModifiers.active?
      return ret
    end

    def pbEndureKOMessage(target)
      return super(target) if !BattleModifiers.active?
      return if BattleModifiers.override(:endure_ko_message, self, target)
      # Fermeté virtuelle : la bulle doit afficher "Fermeté", pas le vrai talent.
      if target.damageState.sturdy && target.ability_id != :STURDY &&
         target.bmod_extra_abilities.include?(:STURDY)
        return target.bmod_with_ability(:STURDY) { super(target) }
      end
      return super(target)
    end

    # Attaques qui retirent écrans/terrain (Anti-Brume, Casse-Brique, Lames
    # Ferraille...) : les effets permanents stricts sont masqués pendant leur
    # effet, elles ne les voient donc pas.
    def pbEffectGeneral(*args)
      return super(*args) if !bmod_masks_removal?
      return BattleModifiers::Locks.hide_protected(@battle) { super(*args) }
    end

    def pbEffectAgainstTarget(*args)
      return super(*args) if !bmod_masks_removal?
      return BattleModifiers::Locks.hide_protected(@battle) { super(*args) }
    end

    def pbShowAnimation(*args)
      return super(*args) if !bmod_masks_removal?
      return BattleModifiers::Locks.hide_protected(@battle) { super(*args) }
    end

    def bmod_masks_removal?
      return false if !BattleModifiers.active? || !BattleModifiers::Locks.any_strict_removable?
      @bmod_remover = BattleModifiers::Locks.remover?(self) if @bmod_remover.nil?
      return @bmod_remover
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
          next effects.send(original, ability, *args) if !BattleModifiers.extra_abilities?
          # Porteur cherché avant l'appel (le handler peut changer le talent), et
          # nom de bulle oublié pour qu'il ne s'affiche pas sur le vrai talent.
          # Idem pour les Pokémon passés au handler (ex. l'attaquant pour Momie).
          owner = AbilityMultiplexer.owner_of(spec[0], ability, args)
          owner&.bmod_clear_shown_ability
          args.each { |a| a.bmod_clear_shown_ability if a.is_a?(Battle::Battler) }
          ret = effects.send(original, ability, *args)
          next ret if !owner
          next AbilityMultiplexer.run_extras(effects.const_get(name), name, spec, owner, args, ret)
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

    def run_extras(hash, name, spec, owner, args, ret)
      mode  = spec[1]
      index = spec[2]
      return ret if mode == :or && ret
      return ret if mode == :first && ret && ret != 0
      # OnSwitchIn est aussi déclenché hors des entrées en jeu (Calque, fin du
      # Gaz Inhibiteur, Paléosynthèse...) : les talents virtuels ne réagissent
      # qu'aux vraies entrées (argument switch_in), sinon leurs effets d'entrée
      # (Brise-Moule, Aéroporté...) se répéteraient.
      # Une seule fois par entrée : Paléosynthèse/Moteur à Quarks rappellent
      # OnSwitchIn avec switch_in = true (Morphing, Imposteur...).
      if name == :OnSwitchIn
        return ret if args[2] != true || !owner.bmod_entry_pending
        owner.bmod_entry_pending = false
      end
      extras = owner.bmod_extra_abilities
      return ret if extras.empty?
      extras.each do |extra|
        call_args = args.clone
        call_args[index] = ret if mode == :chain
        value = owner.bmod_with_ability(extra) { hash.trigger(extra, *call_args) }
        case mode
        when :chain
          ret = value if !value.nil?
        when :or, :first
          next if !value || value == 0
          # L'appelant affiche souvent la bulle après coup (Aquabulle...).
          owner.bmod_show_ability(extra)
          return value
        else   # :each
          ret ||= value
        end
      end
      return ret
    end
  end
end

BattleModifiers::AbilityMultiplexer.install

#===============================================================================
# IA : elle voit les attaques bloquées (:move_fails, effets permanents), les
# multiplicateurs de dégâts (:damage_multipliers) et les dégâts de fin de tour
# (:ai_eor_damage) des gimmicks.
#===============================================================================
class Battle::AI
  alias __bmod_pbPredictMoveFailure pbPredictMoveFailure unless method_defined?(:__bmod_pbPredictMoveFailure)
  def pbPredictMoveFailure
    return true if __bmod_pbPredictMoveFailure
    return false if !BattleModifiers.active?
    move = @move.move
    return true if BattleModifiers::Locks.move_blocked?(@battle, move, false)
    return BattleModifiers.any?(:move_fails, @user.battler, move, [], false)
  end
end

class Battle::AI::AIMove
  alias __bmod_rough_damage rough_damage unless method_defined?(:__bmod_rough_damage)
  def rough_damage
    ret = __bmod_rough_damage
    return ret if ret <= 0 || !BattleModifiers.handles?(:damage_multipliers)
    # Dégâts fixes (Frappe Atlas, Croc Fatal, K.O. en un coup...) : pas de
    # multiplicateurs en combat non plus.
    return ret if @move.is_a?(Battle::Move::FixedDamageMove)
    user   = @ai.user&.battler
    target = @ai.target&.battler
    return ret if !user || !target
    multipliers = {
      :power_multiplier        => 1.0,
      :attack_multiplier       => 1.0,
      :defense_multiplier      => 1.0,
      :final_damage_multiplier => 1.0
    }
    BattleModifiers.trigger(:damage_multipliers, user, target, @move, rough_type, base_power, multipliers)
    factor = multipliers[:power_multiplier] * multipliers[:attack_multiplier] *
             multipliers[:final_damage_multiplier] / multipliers[:defense_multiplier]
    return ret if factor == 1.0
    ret = [(ret * factor).round, 1].max
    # Faux-Chage / Retenue ne mettent jamais K.O.
    ret = target.hp - 1 if @move.nonLethal?(user, target) && ret >= target.hp
    return ret
  end
end

class Battle::AI::AIBattler
  alias __bmod_rough_end_of_round_damage rough_end_of_round_damage unless method_defined?(:__bmod_rough_end_of_round_damage)
  def rough_end_of_round_damage
    ret = __bmod_rough_end_of_round_damage
    return ret if !BattleModifiers.handles?(:ai_eor_damage)
    return BattleModifiers.modify(:ai_eor_damage, ret, battler)
  end
end

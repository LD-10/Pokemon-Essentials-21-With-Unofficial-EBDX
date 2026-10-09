#===============================================================================
# BattleModifiers - moteur de règles ("gimmicks") du Battle Simulator.
#
# Un gimmick (BattleModifiers::Modifier) est enregistré une fois, avec ses
# métadonnées (nom, description, catégorie, portée...) et ses handlers. Les
# hooks posés sur Battle, Battle::Battler, Battle::Move et
# Battle::AbilityEffects (voir "[002] BattleModifiers Hooks.rb") interrogent
# BattleModifiers pendant le combat.
#
# Seuls les gimmicks cochés dans le menu (la "session") sont consultés, et
# uniquement pendant un combat lancé par le simulateur. Sans session active,
# chaque hook se contente d'appeler la méthode d'origine.
#
# Exemple :
#   BattleModifiers.register(:demo_trick_room,
#     name:        "Distorsion permanente",
#     description: "Distorsion est active pendant tout le combat.",
#     category:    :room,
#     scope:       :global
#   ) do |m|
#     m.on(:on_battle_init) { |battle| battle.field.effects[PBEffects::TrickRoom] = 999 }
#   end
#
# La façon dont les valeurs renvoyées par les handlers sont combinées dépend de
# l'événement (voir EVENTS) :
#   trigger  : simple notification, la valeur renvoyée est ignorée.
#   modify   : le handler reçoit la valeur courante en 1er argument et renvoie la
#              nouvelle valeur (nil = inchangée). Les handlers sont chaînés.
#   allow?   : renvoyer false interdit l'action (veto). Toute autre valeur laisse
#              faire.
#   any?     : renvoyer une valeur vraie déclenche l'effet (ex. échec d'attaque).
#   collect  : chaque handler renvoie un tableau ; les tableaux sont concaténés.
#   override : le 1er handler qui renvoie une valeur non-nil remplace la
#              mécanique d'origine (renvoyer true = "c'est géré").
#===============================================================================
module BattleModifiers
  # Événements disponibles : nom => [mode de combinaison, arguments].
  EVENTS = {
    #--- Cycle de vie du combat ---------------------------------------------
    # Avant pbStartBattleCore : les Pokémon ne sont pas encore sur le terrain.
    # C'est le moment de régler @field (météo, terrain, salles) et @sides : les
    # annonces "Le soleil brille." etc. du jeu de base s'affichent ensuite.
    :on_battle_init       => [:trigger,  "battle"],
    # Pokémon envoyés, juste avant les effets d'entrée (talents, objets, pièges).
    :on_battle_start      => [:trigger,  "battle"],
    # Après l'entrée d'un Pokémon (début de combat, switch, remplacement K.O.).
    :on_battler_enter     => [:trigger,  "battle, battler"],
    :before_end_of_round  => [:trigger,  "battle"],
    :on_end_of_round      => [:trigger,  "battle"],
    # Après qu'un Pokémon a fini d'utiliser une attaque.
    :after_move_used      => [:trigger,  "battle, user, move"],
    :on_battle_end        => [:trigger,  "battle, decision"],
    #--- Météo / terrain ----------------------------------------------------
    :can_change_weather   => [:allow,    "battle, user, new_weather"],
    :can_change_terrain   => [:allow,    "battle, user, new_terrain"],
    # Météo effective (après Air Lock / Ciel Gris).
    :effective_weather    => [:modify,   "weather, battle"],
    # Dégâts de météo de fin de tour d'un Pokémon. true = géré par le gimmick.
    :eor_weather_damage   => [:override, "battle, battler"],
    # Soin du Champ Herbu de fin de tour d'un Pokémon. true = géré.
    :eor_terrain_healing  => [:override, "battle, battler"],
    # Après un vrai changement de météo par Battle#pbStartWeather.
    :on_weather_change    => [:trigger,  "battle, old_weather, new_weather"],
    #--- Battler ------------------------------------------------------------
    # Talents "virtuels" ajoutés au talent normal (hasActiveAbility? + handlers
    # de Battle::AbilityEffects). Renvoyer un tableau d'IDs de talents.
    # (Pour des talents fixes côté IA, l'option ai_abilities: de register est
    # plus simple et plus rapide.)
    :extra_abilities      => [:collect,  "battler"],
    # Battler#abilityActive? : renvoyer false neutralise le talent (réel et
    # virtuels) de ce Pokémon. Ne jamais appeler hasActiveAbility? ni
    # abilityActive? sur ce battler dans le handler (récursion infinie).
    :ability_active       => [:allow,    "battler, check_ability"],
    :speed                => [:modify,   "speed, battler"],
    # show_messages est false quand l'IA ne fait qu'une prédiction.
    :can_inflict_status   => [:allow,    "battler, status, user, move, show_messages"],
    :can_lower_stat       => [:allow,    "battler, stat, user, move, show_messages"],
    #--- Attaques -----------------------------------------------------------
    :move_priority        => [:modify,   "priority, user, move"],
    # true = l'attaque échoue complètement. Afficher le message dans le handler
    # seulement si show_message est vrai : l'IA appelle aussi cet événement
    # (show_message = false) pour savoir qu'une attaque va échouer.
    :move_fails           => [:any,      "user, move, targets, show_message"],
    # true = l'attaque échoue contre cette cible.
    :move_fails_against   => [:any,      "user, target, move, show_message"],
    # Efficacité (Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER = neutre, 0 = immunité).
    :type_effectiveness   => [:modify,   "effectiveness, move, move_type, user, target"],
    :base_damage          => [:modify,   "power, user, target, move"],
    # multipliers = { :power_multiplier, :attack_multiplier,
    #                 :defense_multiplier, :final_damage_multiplier }
    :damage_multipliers   => [:trigger,  "user, target, move, type, base_damage, multipliers"],
    # modifiers = { :base_accuracy, :accuracy_stage, :evasion_stage,
    #               :accuracy_multiplier, :evasion_multiplier }
    :accuracy_modifiers   => [:trigger,  "user, target, move, modifiers"],
    # Crans de coup critique ajoutés (comme Puissance / Cri Draconique).
    :critical_stage_bonus => [:modify,   "bonus, user, target, move"],
    # Après Battle::Move#pbCheckDamageAbsorption (Clone, Fantômasque, Tête de
    # Gel) : le handler peut régler target.damageState pour que le coup soit
    # absorbé.
    :damage_absorption    => [:trigger,  "user, target, move"],
    # Avant Battle::Move#pbEndureKOMessage (messages Fantômasque, Fermeté,
    # Ténacité...). true = message géré, celui du jeu n'est pas affiché.
    :endure_ko_message    => [:override, "move, target"],
    #--- IA -----------------------------------------------------------------
    # Estimation par l'IA des dégâts/soins de fin de tour d'un Pokémon (PV
    # perdus, négatif = soin). Les handlers de :damage_multipliers et
    # :move_fails sont déjà pris en compte automatiquement par l'IA.
    :ai_eor_damage        => [:modify,   "damage, battler"]
  }

  # Durée donnée aux effets de terrain/côté rendus permanents (Distorsion,
  # Protection...). Le compte à rebours de fin de tour est bloqué pour eux,
  # et l'IA lit simplement un effet "qui dure longtemps".
  LOCK = 999

  # Catégories, dans l'ordre d'affichage du menu.
  CATEGORIES = [
    [:weather,   _INTL("Météo")],
    [:terrain,   _INTL("Terrains")],
    [:room,      _INTL("Salles & Gravité")],
    [:ai_side,   _INTL("Protections côté IA")],
    [:t_terrain, _INTL("T-Terrains")],
    [:vicious,   _INTL("Vicious Weathers")],
    [:aura_reduce,  _INTL("Boss Auras : réduction des dégâts")],
    [:aura_immune,  _INTL("Boss Auras : immunités et absorption")],
    [:aura_bypass,  _INTL("Boss Auras : contournement")],
    [:aura_protect, _INTL("Boss Auras : protection")],
    [:aura_boost,   _INTL("Boss Auras : boosts automatiques")],
    [:aura_special, _INTL("Boss Auras : spéciales")],
    [:duo_boost, _INTL("Boosts Duo")],
    [:misc,      _INTL("Divers")],
    [:demo,      _INTL("Démo (étape 1)")]
  ]

  SCOPES = {
    :global      => _INTL("Global"),
    :ai_side     => _INTL("IA"),
    :player_side => _INTL("Joueur")
  }

  FORMATS = [:single, :double]

  #=============================================================================
  # Un gimmick enregistré.
  #=============================================================================
  class Modifier
    attr_reader :id, :name, :description, :category, :scope, :formats
    attr_reader :exclusive, :conflicts, :order, :handlers, :ai_abilities

    def initialize(id, options)
      @id          = id
      @name        = options[:name] || id.to_s
      @description = options[:description] || ""
      @category    = options[:category] || :misc
      @scope       = options[:scope] || :global
      # Formats où le gimmick est disponible (:single, :double).
      @formats     = options[:formats] || FORMATS
      # Groupe exclusif : cocher ce gimmick décoche les autres du même groupe
      # (ex. une seule météo à la fois).
      @exclusive   = options[:exclusive]
      # IDs de gimmicks incompatibles (décochés automatiquement).
      @conflicts   = options[:conflicts] || []
      # Ordre d'exécution des handlers et d'affichage (plus petit = premier).
      @order       = options[:order] || 0
      # Talents virtuels donnés à tous les Pokémon de l'IA (Boss Auras).
      @ai_abilities = Array(options[:ai_abilities]).freeze
      @handlers    = {}
    end

    # Ajoute un handler pour un événement de BattleModifiers::EVENTS.
    def on(event, &block)
      if !EVENTS.has_key?(event)
        raise ArgumentError, "BattleModifiers : événement inconnu :#{event} (gimmick :#{@id})"
      end
      raise ArgumentError, "BattleModifiers : handler sans bloc (gimmick :#{@id})" if !block
      (@handlers[event] ||= []).push(block)
      return self
    end

    def available_in?(format)
      return @formats.include?(format)
    end

    def scope_name
      return SCOPES[@scope] || @scope.to_s
    end
  end

  #=============================================================================
  # Les gimmicks actifs pour un combat (sélection du menu + format).
  #=============================================================================
  class Session
    attr_reader   :modifiers, :format, :state
    attr_accessor :battle

    def initialize(modifiers, format)
      @modifiers = modifiers
      @format    = format
      @state     = {}
      @battle    = nil
      @handlers  = {}
    end

    # Liste [[modifier, proc], ...] pour un événement, triée par ordre.
    def handlers(event)
      list = @handlers[event]
      return list if list
      list = []
      @modifiers.each do |mod|
        mod.handlers[event]&.each { |handler| list.push([mod, handler]) }
      end
      @handlers[event] = list.freeze
      return list
    end

    def include?(id)
      return @modifiers.any? { |mod| mod.id == id }
    end

    # Talents virtuels fixes d'un côté (option ai_abilities: des gimmicks).
    def static_abilities(side)
      if !@static_abilities
        ai = @modifiers.map { |mod| mod.ai_abilities }.flatten.uniq
        @static_abilities = { 0 => [].freeze, 1 => ai.freeze }
      end
      return @static_abilities[side] || []
    end

    # Au moins un gimmick donne des talents virtuels ?
    def extra_abilities?
      if @extra_abilities.nil?
        @extra_abilities = !static_abilities(1).empty? || !handlers(:extra_abilities).empty?
      end
      return @extra_abilities
    end
  end

  @registry = {}
  @session  = nil

  module_function

  #=============================================================================
  # Registre
  #=============================================================================
  def register(id, **options)
    mod = Modifier.new(id, options)
    yield mod if block_given?
    @registry[id] = mod
    return mod
  end

  def unregister(id)
    @registry.delete(id)
  end

  def get(id)
    return @registry[id]
  end

  def exists?(id)
    return @registry.has_key?(id)
  end

  # Tous les gimmicks, triés par catégorie, ordre puis ordre d'enregistrement.
  def all
    cat_index = {}
    CATEGORIES.each_with_index { |cat, i| cat_index[cat[0]] = i }
    ret = @registry.values.each_with_index.sort_by do |mod, i|
      [cat_index[mod.category] || CATEGORIES.length, mod.order, i]
    end
    return ret.map { |entry| entry[0] }
  end

  def category_name(category)
    entry = CATEGORIES.find { |cat| cat[0] == category }
    return (entry) ? entry[1] : category.to_s
  end

  # Gimmicks à décocher quand on coche new_id (groupe exclusif + conflits).
  def incompatible_with(new_id, selected_ids)
    new_mod = @registry[new_id]
    return [] if !new_mod
    return selected_ids.select do |id|
      next false if id == new_id
      mod = @registry[id]
      next false if !mod
      next true if new_mod.exclusive && mod.exclusive == new_mod.exclusive
      next true if new_mod.conflicts.include?(id) || mod.conflicts.include?(new_id)
      next false
    end
  end

  #=============================================================================
  # Session
  #=============================================================================
  # Appelé par le lanceur juste avant de créer le combat.
  def start_session(ids, format)
    mods = ids.map { |id| @registry[id] }.compact.select { |mod| mod.available_in?(format) }
    sorted = mods.each_with_index.sort_by { |mod, i| [mod.order, i] }.map { |entry| entry[0] }
    @session = Session.new(sorted, format)
    return @session
  end

  def end_session
    @session = nil
  end

  def session
    return @session
  end

  # Liés par le hook de Battle#pbStartBattle.
  def attach_battle(battle)
    @session.battle = battle if @session && !@session.battle
  end

  def detach_battle(battle)
    @session.battle = nil if @session && @session.battle == battle
  end

  # true pendant un combat du simulateur avec au moins un gimmick actif.
  def active?
    return !@session.nil? && !@session.battle.nil? && !@session.modifiers.empty?
  end

  def battle
    return @session&.battle
  end

  # Données libres pour les gimmicks, remises à zéro à chaque combat.
  def state
    return (@session) ? @session.state : {}
  end

  def format
    return @session&.format
  end

  def double_battle?
    return @session&.format == :double
  end

  # Le gimmick id est-il coché pour le combat en cours ?
  def enabled?(id)
    return !@session.nil? && @session.include?(id)
  end

  # Au moins un gimmick actif écoute cet événement ?
  def handles?(event)
    return active? && !@session.handlers(event).empty?
  end

  #=============================================================================
  # Dispatch
  #=============================================================================
  def trigger(event, *args)
    return if !active?
    @session.handlers(event).each { |mod, handler| call_handler(mod, event, handler, args) }
  end

  def modify(event, value, *args)
    return value if !active?
    @session.handlers(event).each do |mod, handler|
      ret = call_handler(mod, event, handler, [value] + args)
      value = ret if !ret.nil?
    end
    return value
  end

  def allow?(event, *args)
    return true if !active?
    @session.handlers(event).each do |mod, handler|
      return false if call_handler(mod, event, handler, args) == false
    end
    return true
  end

  def any?(event, *args)
    return false if !active?
    @session.handlers(event).each do |mod, handler|
      return true if call_handler(mod, event, handler, args)
    end
    return false
  end

  def collect(event, *args)
    return [] if !active?
    ret = []
    @session.handlers(event).each do |mod, handler|
      value = call_handler(mod, event, handler, args)
      ret.concat(Array(value)) if value
    end
    return ret
  end

  def override(event, *args)
    return nil if !active?
    @session.handlers(event).each do |mod, handler|
      ret = call_handler(mod, event, handler, args)
      return ret if !ret.nil?
    end
    return nil
  end

  # Ajoute le gimmick et l'événement au message d'une erreur levée par un
  # handler, pour savoir immédiatement quel gimmick a planté.
  def call_handler(mod, event, handler, args)
    return handler.call(*args)
  rescue StandardError => e
    raise e if e.message.start_with?("[BattleModifiers")
    raise e.exception("[BattleModifiers :#{mod.id} / :#{event}] #{e.message}")
  end

  #=============================================================================
  # Aides pour écrire des gimmicks
  #=============================================================================
  # Côté 0 = joueur, côté 1 = IA.
  def ai_battler?(battler)
    return battler.opposes?
  end

  def player_battler?(battler)
    return !battler.opposes?
  end

  def ai_side(battle = nil)
    battle ||= self.battle
    return battle&.sides[1]
  end

  def player_side(battle = nil)
    battle ||= self.battle
    return battle&.sides[0]
  end

  # Un gimmick actif donne-t-il des talents virtuels ?
  def extra_abilities?
    return active? && @session.extra_abilities?
  end

  # Talents virtuels d'un battler (renvoie toujours un nouveau tableau).
  def extra_abilities_for(battler)
    return [] if !extra_abilities?
    ret = @session.static_abilities(battler.idxOwnSide).dup
    return ret if @session.handlers(:extra_abilities).empty?
    ret.concat(collect(:extra_abilities, battler))
    ret.map! { |abil| (abil.is_a?(Symbol)) ? abil : GameData::Ability.try_get(abil)&.id }
    ret.compact!
    ret.uniq!
    return ret
  end
end

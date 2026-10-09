#===============================================================================
# BattleModifiers - outils partagés par les gimmicks des étapes 2 à 6.
#
# Locks : effets rendus permanents (météo, terrain, salles, protections d'un
# côté). On ne stocke jamais de météo ou de terrain "maison" dans @field : un
# T-Terrain est un vrai Champ Herbu (:Grassy...) plus un verrou rangé dans
# BattleModifiers.state. Tout le jeu de base (dégâts, talents, objets, IA,
# EBDX) continue donc de reconnaître l'effet.
#
# Deux niveaux de verrou :
#   strict: false -> une attaque ou un talent peut retirer ou remplacer l'effet
#                    (Anti-Brume, Casse-Brique, Danse Pluie...), qui revient
#                    ensuite tout seul.
#   strict: true  -> l'effet ne peut pas être retiré ni remplacé (T-Terrains,
#                    Vicious Weathers, salles). Seules les météos primales
#                    peuvent remplacer une météo stricte, tant que leur
#                    porteur reste sur le terrain.
#
# Les hooks de "[002] BattleModifiers Hooks.rb" consultent ce module :
# pbStartWeather/pbStartTerrain (veto), pbEORCountDown* (pas de décompte),
# Battle::Move (attaques bloquées, effets masqués pendant Anti-Brume...), IA.
#===============================================================================
module BattleModifiers
  module Locks
    PRIMAL_WEATHERS = [:HarshSun, :HeavyRain, :StrongWinds]

    # Attaques qui inversent une salle (une 2e utilisation l'annule).
    ROOM_MOVES = {
      "StartSlowerBattlersActFirst"            => [PBEffects::TrickRoom,  _INTL("Mais la Distorsion est permanente !")],
      "StartNegateHeldItems"                   => [PBEffects::MagicRoom,  _INTL("Mais la Zone Magique est permanente !")],
      "StartSwapAllBattlersBaseDefensiveStats" => [PBEffects::WonderRoom, _INTL("Mais la Zone Étrange est permanente !")]
    }

    TERRAIN_MOVES = {
      "StartElectricTerrain" => :Electric,
      "StartGrassyTerrain"   => :Grassy,
      "StartMistyTerrain"    => :Misty,
      "StartPsychicTerrain"  => :Psychic
    }

    # Classes des attaques qui retirent des effets de côté ou le terrain.
    REMOVER_CLASSES = [
      :RemoveScreens,                         # Casse-Brique, Psycho-Croc, Rage Taurine
      :LowerTargetEvasion1RemoveSideEffects,  # Anti-Brume
      :SwapSideEffects,                       # Change Côté
      :RemoveAllScreensAndSafeguard,          # Mue Obscure (Pokémon Obscurs)
      :RemoveTerrain,                         # Lames Ferraille
      :RemoveTerrainIceSpinner                # Pirouette Glace (Gen 9 Pack)
    ]

    # Valeur au-delà de laquelle un compteur d'effet de côté vient forcément
    # d'un verrou (les vrais effets durent 8 tours au plus).
    LOCK_THRESHOLD = 100

    @hiding = false
    @hidden = nil

    module_function

    def state
      return BattleModifiers.state
    end

    #===========================================================================
    # Pose des verrous (dans un handler :on_battle_init)
    #===========================================================================
    # Effet d'un côté (Protection, Vent Arrière...). side : 0 joueur, 1 IA.
    def lock_side_effect(battle, side, effect, strict = false)
      battle.sides[side].effects[effect] = LOCK
      (state[:side_locks] ||= {})[[side, effect]] = strict
    end

    # Effet de tout le terrain (Distorsion, Gravité...). Toujours strict.
    def lock_field_effect(battle, effect)
      battle.field.effects[effect] = LOCK
      (state[:field_locks] ||= {})[effect] = true
    end

    # Options :
    #   strict             : voir l'en-tête du fichier
    #   ignores_cloud_nine : Ciel Gris n'annule pas cette météo (Air Lock oui)
    #   cloud_nine_message : phrase affichée après celle de Ciel Gris
    #   block_message      : phrase affichée quand un talent essaie de changer
    #                        la météo, ou quand une attaque météo échoue
    def lock_weather(battle, weather, **options)
      battle.defaultWeather = weather
      state[:weather_lock] = options.merge(:weather => weather)
    end

    # Options : strict, block_message (comme lock_weather).
    def lock_terrain(battle, terrain, **options)
      battle.defaultTerrain = terrain
      state[:terrain_lock] = options.merge(:terrain => terrain)
    end

    #===========================================================================
    # Lecture
    #===========================================================================
    def weather_lock
      return state[:weather_lock]
    end

    def terrain_lock
      return state[:terrain_lock]
    end

    def side_locked?(side, effect)
      locks = state[:side_locks]
      return !locks.nil? && locks.has_key?([side, effect])
    end

    def field_locked?(effect)
      locks = state[:field_locks]
      return !locks.nil? && locks.has_key?(effect)
    end

    # Le terrain verrouillé est-il celui-ci et en place ?
    def terrain_active?(battle, terrain)
      lock = terrain_lock
      return !lock.nil? && lock[:terrain] == terrain && battle.field.terrain == terrain
    end

    # Y a-t-il quelque chose à cacher aux attaques qui retirent des effets ?
    def any_strict_removable?
      return true if terrain_lock && terrain_lock[:strict]
      locks = state[:side_locks]
      return !locks.nil? && locks.any? { |_key, strict| strict }
    end

    def remover?(move)
      REMOVER_CLASSES.each do |name|
        next if !Battle::Move.const_defined?(name, false)
        return true if move.is_a?(Battle::Move.const_get(name, false))
      end
      return false
    end

    #===========================================================================
    # Règles consultées par les hooks
    #===========================================================================
    def weather_change_allowed?(new_weather)
      lock = weather_lock
      return true if !lock || !lock[:strict]
      return true if new_weather == lock[:weather]
      return PRIMAL_WEATHERS.include?(new_weather)
    end

    def terrain_change_allowed?(new_terrain)
      lock = terrain_lock
      return true if !lock || !lock[:strict]
      return new_terrain == lock[:terrain]
    end

    def show_block_message(battle, kind)
      lock = (kind == :weather) ? weather_lock : terrain_lock
      battle.pbDisplay(lock[:block_message]) if lock && lock[:block_message]
    end

    # Météo vue par le jeu (Battle#pbWeather) : Ciel Gris peut être ignoré.
    def effective_weather(battle, weather)
      return weather if weather != :None
      lock = weather_lock
      return weather if !lock || !lock[:ignores_cloud_nine]
      return weather if battle.field.weather != lock[:weather]
      return weather if battle.allBattlers.any? { |b| b.hasActiveAbility?(:AIRLOCK) }
      return battle.field.weather
    end

    # L'attaque échoue-t-elle à cause d'un effet permanent ? (l'IA appelle
    # aussi cette méthode, avec show_message = false)
    def move_blocked?(battle, move, show_message)
      code = move.function_code
      room = ROOM_MOVES[code]
      if room && field_locked?(room[0])
        battle.pbDisplay(room[1]) if show_message
        return true
      end
      lock = weather_lock
      if lock && lock[:strict] && move.is_a?(Battle::Move::WeatherMove) &&
         move.weatherType != lock[:weather] &&
         !PRIMAL_WEATHERS.include?(battle.field.weather)   # Message du jeu dans ce cas
        battle.pbDisplay(lock[:block_message] || _INTL("But it failed!")) if show_message
        return true
      end
      lock = terrain_lock
      new_terrain = TERRAIN_MOVES[code]
      if lock && lock[:strict] && new_terrain && new_terrain != lock[:terrain]
        battle.pbDisplay(lock[:block_message] || _INTL("But it failed!")) if show_message
        return true
      end
      return false
    end

    # Exécute le bloc en cachant les effets permanents stricts (mis à 0, terrain
    # à :None), puis remet exactement les valeurs d'avant.
    def hide_protected(battle)
      return yield if @hiding || !BattleModifiers.active?
      saved = []
      (state[:side_locks] || {}).each do |key, strict|
        next if !strict
        effects = battle.sides[key[0]].effects
        saved.push([effects, key[1], effects[key[1]]])
        effects[key[1]] = 0
      end
      saved_terrain = nil
      lock = terrain_lock
      if lock && lock[:strict] && battle.field.terrain == lock[:terrain]
        saved_terrain = battle.field.terrain
        battle.field.terrain = :None
      end
      @hidden = saved
      @hiding = true
      begin
        return yield
      ensure
        @hiding = false
        @hidden = nil
        saved.each { |effects, effect, value| effects[effect] = value }
        battle.field.terrain = saved_terrain if saved_terrain
      end
    end

    # Pendant hide_protected : remet un instant la vraie valeur d'un effet de
    # côté caché (ex. Brume permanente contre la baisse d'Esquive d'Anti-Brume).
    def with_hidden_side_effect(battle, side, effect)
      entry = nil
      if @hiding && @hidden
        effects = battle.sides[side].effects
        entry = @hidden.find { |e| e[0].equal?(effects) && e[1] == effect }
      end
      return yield if !entry || entry[2] == 0
      entry[0][effect] = entry[2]
      begin
        return yield
      ensure
        entry[0][effect] = 0
      end
    end

    # Terrain strict en place : les attaques qui retirent le terrain n'y
    # touchent pas.
    def terrain_unremovable?(battle)
      return false if !BattleModifiers.active?
      lock = terrain_lock
      return !lock.nil? && lock[:strict] && battle.field.terrain == lock[:terrain]
    end

    # Remet en place ce qui a été retiré. timing : :enter (entrée en jeu),
    # :move (après une attaque) ou :round (fin de tour). Les effets non stricts
    # ne reviennent qu'en fin de tour : ils ont bien été retirés pour ce tour.
    def reconcile(battle, timing)
      reconcile_sides(battle, timing)
      reconcile_field(battle)
      reconcile_weather(battle, timing)
      reconcile_terrain(battle, timing)
    end

    def reconcile_sides(battle, timing)
      locks = state[:side_locks]
      return if !locks
      locks.each do |key, strict|
        side, effect = key
        # Change Côté a pu donner un effet permanent à l'autre côté.
        other = battle.sides[1 - side].effects
        other[effect] = 0 if other[effect] > LOCK_THRESHOLD && !side_locked?(1 - side, effect)
        next if !strict && timing != :round
        battle.sides[side].effects[effect] = LOCK
      end
    end

    def reconcile_field(battle)
      locks = state[:field_locks]
      return if !locks
      locks.each_key { |effect| battle.field.effects[effect] = LOCK }
    end

    def reconcile_weather(battle, timing)
      lock = weather_lock
      return if !lock
      weather = battle.field.weather
      return if weather == lock[:weather] || PRIMAL_WEATHERS.include?(weather)
      # Météo non stricte remplacée (Danse Pluie...) : defaultWeather la remet
      # quand l'autre météo se termine.
      return if !lock[:strict] && (weather != :None || timing != :round)
      battle.pbStartWeather(nil, lock[:weather])
      battle.field.weatherDuration = -1 if battle.field.weather == lock[:weather]
    end

    def reconcile_terrain(battle, timing)
      lock = terrain_lock
      return if !lock
      terrain = battle.field.terrain
      return if terrain == lock[:terrain]
      # Terrain non strict : remplacé par un autre Champ, defaultTerrain le remet
      # à la fin de celui-ci ; retiré (Anti-Brume...), il revient en fin de tour.
      return if !lock[:strict] && (terrain != :None || timing != :round)
      battle.pbStartTerrain(nil, lock[:terrain], false)
    end

    #===========================================================================
    # Lame de Fond (Screen Cleaner) n'a pas de classe d'attaque : on enveloppe
    # son handler pour qu'elle ne voie pas les protections strictes.
    #===========================================================================
    # Remplace le handler hash[key] par un proc qui reçoit l'original en plus.
    # Sans effet si c'est déjà fait (F12 recrée les handlers d'origine).
    def install_guard(hash, key, &body)
      original = hash[key]
      return if !original || original.instance_variable_get(:@bmod_guard)
      guard = proc { |*args| body.call(original, *args) }
      guard.instance_variable_set(:@bmod_guard, true)
      hash.add(key, guard)
    end

    def install_ability_guards
      on_switch_in = Battle::AbilityEffects::OnSwitchIn
      # Lame de Fond n'a pas de classe d'attaque : elle ne doit pas voir les
      # protections strictes.
      install_guard(on_switch_in, :SCREENCLEANER) do |original, ability, battler, battle, switch_in|
        next original.call(ability, battler, battle, switch_in) if !BattleModifiers.active?
        next Locks.hide_protected(battle) { original.call(ability, battler, battle, switch_in) }
      end
      # Moteur à Hadrons (Gen 9 Pack) affiche "turned the ground into Electric
      # Terrain" même quand un T-Terrain refuse le changement.
      install_guard(on_switch_in, :HADRONENGINE) do |original, ability, battler, battle, switch_in|
        if !BattleModifiers.active? || battle.field.terrain == :Electric ||
           Locks.terrain_change_allowed?(:Electric)
          next original.call(ability, battler, battle, switch_in)
        end
        battle.pbShowAbilitySplash(battler)
        battle.pbStartTerrain(battler, :Electric)   # Refusé : message + bulle cachée
      end
      # Pouls Orichalque : même problème avec le Soleil sous une météo stricte.
      install_guard(on_switch_in, :ORICHALCUMPULSE) do |original, ability, battler, battle, switch_in|
        if !BattleModifiers.active? || [:Sun, :HarshSun].include?(battler.effectiveWeather) ||
           Locks.weather_change_allowed?(:Sun)
          next original.call(ability, battler, battle, switch_in)
        end
        battle.pbStartWeatherAbility(:Sun, battler)   # Refusé : message + bulle cachée
      end
      # Ciel Gris annonce "les effets de la météo disparaissent" à chaque
      # déclenchement (entrée, Échange, Imitation...) : on corrige juste après
      # quand la météo verrouillée l'ignore.
      install_guard(on_switch_in, :CLOUDNINE) do |original, ability, battler, battle, switch_in|
        ret = original.call(ability, battler, battle, switch_in)
        lock = (BattleModifiers.active?) ? Locks.weather_lock : nil
        if lock && lock[:ignores_cloud_nine] && lock[:cloud_nine_message] &&
           battle.field.weather == lock[:weather] &&
           battle.allBattlers.none? { |b| b.hasActiveAbility?(:AIRLOCK) }
          battle.pbDisplay(lock[:cloud_nine_message])
        end
        next ret
      end
    end

    # IA : Lames Ferraille, Pirouette Glace et Anti-Brume comptent comme s'ils
    # retiraient le terrain. On annule ce calcul quand le terrain est verrouillé.
    def install_ai_guards
      [[Battle::AI::Handlers::MoveEffectScore, ["RemoveTerrain", "RemoveTerrainIceSpinner"]],
       [Battle::AI::Handlers::MoveEffectAgainstTargetScore, ["LowerTargetEvasion1RemoveSideEffects"]]].each do |hash, codes|
        codes.each do |code|
          install_guard(hash, code) do |original, score, *rest|
            ai     = rest[-2]
            battle = rest[-1]
            ret = original.call(score, *rest)
            next ret if !ret.is_a?(Numeric) || !Locks.terrain_unremovable?(battle)
            if code == "LowerTargetEvasion1RemoveSideEffects"
              # rest = [move, user, target, ai, battle] : Anti-Brume ne compte le
              # terrain qu'en Gen 8+ et contre un adversaire.
              next ret if Settings::MECHANICS_GENERATION < 8 || !rest[2].opposes?(rest[1])
            end
            next ret + ai.get_score_for_terrain(battle.field.terrain, rest[1])
          end
        end
      end
    end
  end

  #=============================================================================
  # Petites aides pour écrire les gimmicks.
  #=============================================================================
  module Tools
    module_function

    # Pokémon de l'IA actifs (non K.O.).
    def ai_battlers(battle)
      return battle.allBattlers.select { |b| BattleModifiers.ai_battler?(b) }
    end

    # Hausse de stats "venant d'un allié" (Coaching, Rugissement...) :
    # stats = { :ATTACK => 1, ... }, cause = nom affiché ("Coaching").
    # Une seule animation par Pokémon. Contraire inverse la hausse, comme avec
    # la vraie attaque.
    def raise_stats(battler, stats, cause)
      show_anim = true
      stats.each do |stat, amount|
        next if !battler.pbCanRaiseStatStage?(stat, battler, nil)
        if battler.pbRaiseStatStageByCause(stat, amount, battler, cause, show_anim)
          show_anim = false
        end
      end
    end
  end
end

BattleModifiers::Locks.install_ability_guards
BattleModifiers::Locks.install_ai_guards

#===============================================================================
# Étape 5 - Boss Auras.
#
# Chaque aura donne un talent à TOUS les Pokémon de l'IA, en plus de leur
# propre talent (talents "virtuels", voir "[002] BattleModifiers Hooks.rb").
# Le talent fonctionne exactement comme le vrai : mêmes handlers du jeu, même
# bulle de talent, même contre-jeu (Brise Moule ignore les auras défensives,
# Suc Digestif / Force Ajoutée les neutralisent sur ce Pokémon). Échange,
# Imitation, Ten-Danse... ne copient pas les auras.
#
# Trois auras ont un code à part : Gaz Inhibiteur (neutralise seulement les
# talents du joueur), Fantômasque et Tête de Gel (réservés à Mimiqui et
# Bekaglaçon dans le jeu de base).
#===============================================================================
module BattleSimulator
  module BossAuras
    # [id du gimmick, talent, nom affiché, catégorie, description, formats]
    LIST = [
      #--- Réduction des dégâts ------------------------------------------------
      [:aura_fur_coat,      :FURCOAT,      _INTL("Toison Épaisse"),  :aura_reduce,
       _INTL("Dégâts physiques reçus divisés par 2.")],
      [:aura_ice_scales,    :ICESCALES,    _INTL("Écailles Glacées"), :aura_reduce,
       _INTL("Dégâts spéciaux reçus divisés par 2.")],
      [:aura_fluffy,        :FLUFFY,       _INTL("Boule de Poils"),  :aura_reduce,
       _INTL("Dégâts des attaques de contact divisés par 2, mais Feu x2.")],
      [:aura_thick_fat,     :THICKFAT,     _INTL("Isograisse"),      :aura_reduce,
       _INTL("Dégâts des attaques Feu et Glace divisés par 2.")],
      [:aura_solid_rock,    :SOLIDROCK,    _INTL("Solide Roc"),      :aura_reduce,
       _INTL("Dégâts des attaques super efficaces x0,75.")],
      [:aura_multiscale,    :MULTISCALE,   _INTL("Multiécaille"),    :aura_reduce,
       _INTL("Dégâts divisés par 2 quand le Pokémon a tous ses PV.")],
      [:aura_heatproof,     :HEATPROOF,    _INTL("Ignifugé"),        :aura_reduce,
       _INTL("Dégâts Feu et dégâts de brûlure divisés par 2.")],
      [:aura_water_bubble,  :WATERBUBBLE,  _INTL("Aquabulle"),       :aura_reduce,
       _INTL("Dégâts Feu divisés par 2, immunité à la brûlure, attaques Eau x2.")],
      [:aura_friend_guard,  :FRIENDGUARD,  _INTL("Garde-Ami"),       :aura_reduce,
       _INTL("Dégâts reçus par le partenaire x0,75 (le porteur n'est pas protégé)."), [:double]],
      #--- Immunités et absorption ---------------------------------------------
      [:aura_wonder_guard,  :WONDERGUARD,  _INTL("Garde Mystik"),    :aura_immune,
       _INTL("Toute l'équipe IA ne subit que les attaques super efficaces (les dégâts indirects passent).")],
      [:aura_levitate,      :LEVITATE,     _INTL("Lévitation"),      :aura_immune,
       _INTL("Immunité aux attaques Sol (le Pokémon ne touche plus le sol).")],
      [:aura_water_absorb,  :WATERABSORB,  _INTL("Absorbe-Eau"),     :aura_immune,
       _INTL("Les attaques Eau soignent 1/4 des PV au lieu de blesser.")],
      [:aura_volt_absorb,   :VOLTABSORB,   _INTL("Absorbe-Volt"),    :aura_immune,
       _INTL("Les attaques Électrik soignent 1/4 des PV au lieu de blesser.")],
      [:aura_earth_eater,   :EARTHEATER,   _INTL("Absorbe-Terre"),   :aura_immune,
       _INTL("Les attaques Sol soignent 1/4 des PV au lieu de blesser.")],
      [:aura_flash_fire,    :FLASHFIRE,    _INTL("Torche"),          :aura_immune,
       _INTL("Immunité au Feu ; touché par du Feu, ses attaques Feu sont renforcées.")],
      [:aura_well_baked,    :WELLBAKEDBODY, _INTL("Bien Cuit"),      :aura_immune,
       _INTL("Immunité au Feu ; touché par du Feu, Défense +2.")],
      [:aura_wind_rider,    :WINDRIDER,    _INTL("Aéroporté"),       :aura_immune,
       _INTL("Immunité aux attaques de vent (Attaque +1 à la place) ; Attaque +1 sous Vent Arrière.")],
      [:aura_soundproof,    :SOUNDPROOF,   _INTL("Anti-Bruit"),      :aura_immune,
       _INTL("Immunité aux attaques sonores.")],
      [:aura_bulletproof,   :BULLETPROOF,  _INTL("Pare-Balles"),     :aura_immune,
       _INTL("Immunité aux bombes et projectiles (Ball'Ombre, Bombe Beurk...).")],
      [:aura_magic_guard,   :MAGICGUARD,   _INTL("Garde Magik"),     :aura_immune,
       _INTL("Seules les attaques blessent : ni météo, ni poison, ni pièges, ni contrecoup.")],
      [:aura_purifying_salt, :PURIFYINGSALT, _INTL("Sel Purificateur"), :aura_immune,
       _INTL("Immunité aux statuts ; dégâts Spectre divisés par 2.")],
      #--- Contournement ------------------------------------------------------
      [:aura_unaware,       :UNAWARE,      _INTL("Inconscient"),     :aura_bypass,
       _INTL("Ignore les changements de stats de l'adversaire (attaque et défense).")],
      [:aura_mold_breaker,  :MOLDBREAKER,  _INTL("Brise Moule"),     :aura_bypass,
       _INTL("Les attaques de l'IA ignorent les talents défensifs du joueur.")],
      [:aura_infiltrator,   :INFILTRATOR,  _INTL("Infiltration"),    :aura_bypass,
       _INTL("Ignore Protection, Mur Lumière, Voile Aurore, Rune Protect, Brume et Clone.")],
      [:aura_unseen_fist,   :UNSEENFIST,   _INTL("Poing Invisible"), :aura_bypass,
       _INTL("Les attaques de contact de l'IA passent à travers Abri et compagnie.")],
      #--- Protection ---------------------------------------------------------
      [:aura_magic_bounce,  :MAGICBOUNCE,  _INTL("Miroir Magik"),    :aura_protect,
       _INTL("Renvoie les attaques de statut (Toxik, Picots, Cage-Éclair...).")],
      [:aura_mirror_armor,  :MIRRORARMOR,  _INTL("Armure Miroir"),   :aura_protect,
       _INTL("Renvoie les baisses de stats à leur auteur.")],
      [:aura_clear_body,    :CLEARBODY,    _INTL("Corps Sain"),      :aura_protect,
       _INTL("Les stats ne peuvent pas être baissées par l'adversaire.")],
      [:aura_shield_dust,   :SHIELDDUST,   _INTL("Écran Poudre"),    :aura_protect,
       _INTL("Bloque les effets secondaires des attaques reçues.")],
      [:aura_sturdy,        :STURDY,       _INTL("Fermeté"),         :aura_protect,
       _INTL("Survit avec 1 PV à un coup fatal s'il a tous ses PV ; immunité aux attaques K.O. en un coup.")],
      [:aura_disguise,      :DISGUISE,     _INTL("Fantômasque"),     :aura_protect,
       _INTL("Le 1er coup reçu par chaque Pokémon est absorbé (il perd ensuite 1/8 de ses PV, sauf Garde Magik).")],
      [:aura_pastel_veil,   :PASTELVEIL,   _INTL("Voile Pastel"),    :aura_protect,
       _INTL("Le Pokémon et son partenaire ne peuvent pas être empoisonnés.")],
      [:aura_overcoat,      :OVERCOAT,     _INTL("Envelocape"),      :aura_protect,
       _INTL("Immunité aux dégâts de météo et aux poudres (Spore, Poudre Dodo...).")],
      [:aura_good_as_gold,  :GOODASGOLD,   _INTL("Corps en Or"),     :aura_protect,
       _INTL("Immunité aux attaques de statut de l'adversaire.")],
      [:aura_aroma_veil,    :AROMAVEIL,    _INTL("Aroma-Voile"),     :aura_protect,
       _INTL("Protège de Provoc, Encore, Entrave, Tourmente, Anti-Soin et de l'attirance.")],
      [:aura_sweet_veil,    :SWEETVEIL,    _INTL("Gluco-Voile"),     :aura_protect,
       _INTL("Le Pokémon et son partenaire ne peuvent pas être endormis.")],
      [:aura_flower_veil,   :FLOWERVEIL,   _INTL("Flora-Voile"),     :aura_protect,
       _INTL("Les Pokémon Plante de l'IA sont protégés des baisses de stats et des statuts.")],
      #--- Boosts automatiques -----------------------------------------------
      [:aura_steam_engine,  :STEAMENGINE,  _INTL("Turbine"),         :aura_boost,
       _INTL("Touché par une attaque Feu ou Eau : Vitesse +6.")],
      [:aura_wind_power,    :WINDPOWER,    _INTL("Turbine Éolienne"), :aura_boost,
       _INTL("Touché par une attaque de vent : chargé, sa prochaine attaque Électrik est doublée.")],
      [:aura_guard_dog,     :GUARDDOG,     _INTL("Chien de Garde"),  :aura_boost,
       _INTL("Intimidation augmente l'Attaque au lieu de la baisser ; ne peut pas être forcé à partir.")],
      [:aura_grass_pelt,    :GRASSPELT,    _INTL("Toison Herbue"),   :aura_boost,
       _INTL("Défense x1,5 sur Champ Herbu (à combiner avec un Champ Herbu ou T-Herbu).")],
      [:aura_stamina,       :STAMINA,      _INTL("Endurance"),       :aura_boost,
       _INTL("Défense +1 à chaque attaque reçue.")],
      [:aura_weak_armor,    :WEAKARMOR,    _INTL("Armurouillée"),    :aura_boost,
       _INTL("Touché par une attaque physique : Défense -1, Vitesse +2.")],
      [:aura_anger_shell,   :ANGERSHELL,   _INTL("Courroupace"),     :aura_boost,
       _INTL("Passé sous la moitié de ses PV : Attaque, Atq. Spé. et Vitesse +1, Défenses -1.")],
      #--- Spéciales -----------------------------------------------------------
      [:aura_neutralizing_gas, :NEUTRALIZINGGAS, _INTL("Gaz Inhibiteur"), :aura_special,
       _INTL("Les talents des Pokémon du JOUEUR n'ont aucun effet ; l'IA garde les siens (et ses auras).")],
      [:aura_ice_face,      :ICEFACE,      _INTL("Tête de Gel"),     :aura_special,
       _INTL("Le 1er coup physique reçu par chaque Pokémon est absorbé ; se reforme si la grêle commence ou à l'entrée sous la grêle.")]
    ]

    # Auras qui ne passent pas par les talents virtuels.
    CUSTOM = [:NEUTRALIZINGGAS, :DISGUISE, :ICEFACE]

    module_function

    # Clé d'un Pokémon pour tout le combat (même après un switch).
    def pokemon_key(battler)
      return [battler.idxOwnSide, battler.pokemonIndex]
    end

    def broken?(kind, battler)
      list = BattleModifiers.state[kind]
      return !list.nil? && list[pokemon_key(battler)]
    end

    def set_broken(kind, battler, value)
      (BattleModifiers.state[kind] ||= {})[pokemon_key(battler)] = value
    end

    # Ce coup peut-il être absorbé par une aura Fantômasque / Tête de Gel ?
    # (même conditions que le jeu : pas Brise Moule, pas Clone, et le vrai
    # talent de Mimiqui/Bekaglaçon garde son propre code)
    def can_absorb?(battle, target, real_ability, user)
      return false if !BattleModifiers.ai_battler?(target)
      return false if target.ability_id == real_ability
      # Dégâts de confusion (user == target) : le Brise Moule d'une autre
      # attaque (battle.moldBreaker peut rester vrai après un échec) ne compte pas.
      return false if battle.moldBreaker && !(user && user.index == target.index)
      ds = target.damageState
      return false if ds.substitute || ds.disguise || ds.iceFace
      return true
    end

    # Affiche la bulle d'un talent d'aura puis le message.
    def show_splash(battle, battler, ability, message = nil)
      battler.bmod_with_ability(ability) do
        battle.pbShowAbilitySplash(battler)
        battle.pbDisplay(message) if message
        battle.pbHideAbilitySplash(battler)
      end
    end

    def restore_ice_face(battle, battler)
      return if !broken?(:aura_ice_face_broken, battler)
      set_broken(:aura_ice_face_broken, battler, false)
      (BattleModifiers.state[:aura_ice_face_restore] ||= {}).delete(pokemon_key(battler))
      show_splash(battle, battler, :ICEFACE,
                  _INTL("{1}'s Ice Face was restored!", battler.pbThis))
    end
  end
end

#-------------------------------------------------------------------------------
# Enregistrement
#-------------------------------------------------------------------------------
BattleSimulator::BossAuras::LIST.each_with_index do |entry, i|
  id, ability, name, category, description, formats = entry
  custom = BattleSimulator::BossAuras::CUSTOM.include?(ability)
  options = {
    name:         name,
    description:  description,
    category:     category,
    scope:        :ai_side,
    order:        i,
    ai_abilities: (custom) ? [] : [ability]
  }
  options[:formats] = formats if formats
  BattleModifiers.register(id, **options)
end

#-------------------------------------------------------------------------------
# Toison Herbue : le handler du jeu (DamageCalcFromTarget) renforce aussi
# contre les attaques spéciales. En simulateur : Défense seulement (attaques
# physiques + Choc Psy), comme dans les jeux et Showdown.
#-------------------------------------------------------------------------------
BattleModifiers::Locks.install_guard(Battle::AbilityEffects::DamageCalcFromTarget, :GRASSPELT) do |original, ability, user, target, move, mults, power, type|
  if BattleModifiers.active? && !move.physicalMove?(type) &&
     move.function_code != "UseTargetDefenseInsteadOfTargetSpDef"
    next
  end
  next original.call(ability, user, target, move, mults, power, type)
end

#-------------------------------------------------------------------------------
# Gaz Inhibiteur : seuls les talents du joueur sont neutralisés. (Un vrai Gaz
# Inhibiteur donné en talent virtuel neutraliserait aussi l'IA et ses auras.)
#-------------------------------------------------------------------------------
BattleModifiers.get(:aura_neutralizing_gas).tap do |m|
  m.on(:ability_active) do |battler, check_ability|
    if BattleModifiers.ai_battler?(battler)
      # L'aura remplace un vrai Gaz Inhibiteur de l'IA, qui neutraliserait
      # aussi son partenaire et ses auras.
      next false if check_ability == :NEUTRALIZINGGAS ||
                    (check_ability.is_a?(Array) && check_ability.include?(:NEUTRALIZINGGAS))
      next true
    end
    # Talents qu'aucun Gaz Inhibiteur ne neutralise (Déguisement...), et
    # Bouclier Talent. Ces deux tests n'appellent pas abilityActive?.
    next true if battler.unstoppableAbility?
    next true if battler.respond_to?(:activeAbilityShield?) && battler.activeAbilityShield?(check_ability)
    next false
  end
  m.on(:on_battle_start) do |battle|
    holder = BattleModifiers::Tools.ai_battlers(battle).first
    next if !holder
    BattleSimulator::BossAuras.show_splash(battle, holder, :NEUTRALIZINGGAS,
                                           _INTL("Neutralizing gas filled the area!"))
  end
end

# Message d'envoi (pbMessagesOnReplace) : il teste Illusion avec
# pbCheckGlobalAbility(:NEUTRALIZINGGAS), qui ne voit pas l'aura. Pendant ce
# message seulement, l'aura compte comme un vrai Gaz Inhibiteur pour le joueur.
class Battle
  alias __bsim_ng_pbMessagesOnReplace pbMessagesOnReplace unless method_defined?(:__bsim_ng_pbMessagesOnReplace)
  def pbMessagesOnReplace(idxBattler, idxParty)
    pkmn = pbParty(idxBattler)[idxParty]
    # Mêmes conditions que activeAbilityShield? du Gen 9 Pack.
    shield = pkmn && pkmn.hasItem?(:ABILITYSHIELD) &&
             @field.effects[PBEffects::MagicRoom] == 0 &&
             !(@corrosiveGas && @corrosiveGas[idxBattler % 2][idxParty])
    @bsim_aura_gas = BattleModifiers.active? && BattleModifiers.enabled?(:aura_neutralizing_gas) &&
                     !opposes?(idxBattler) && pkmn && !shield
    begin
      return __bsim_ng_pbMessagesOnReplace(idxBattler, idxParty)
    ensure
      @bsim_aura_gas = false
    end
  end

  alias __bsim_ng_pbCheckGlobalAbility pbCheckGlobalAbility unless method_defined?(:__bsim_ng_pbCheckGlobalAbility)
  def pbCheckGlobalAbility(*args)
    if @bsim_aura_gas && args[0] == :NEUTRALIZINGGAS
      return BattleModifiers::Tools.ai_battlers(self).first || true
    end
    return __bsim_ng_pbCheckGlobalAbility(*args)
  end
end

# Un vrai Gaz Inhibiteur de l'IA ne fait rien sous l'aura : l'aura l'a déjà
# annoncé, et les talents de l'IA (Illusion, Début Calme...) ne doivent pas
# être touchés.
BattleModifiers::Locks.install_guard(Battle::AbilityEffects::OnSwitchIn, :NEUTRALIZINGGAS) do |original, ability, battler, battle, switch_in|
  next if BattleModifiers.active? && BattleModifiers.enabled?(:aura_neutralizing_gas) &&
          BattleModifiers.ai_battler?(battler)
  next original.call(ability, battler, battle, switch_in)
end

class Battle::Battler
  # Sous l'aura, la fin d'un vrai Gaz Inhibiteur ne change rien (sauf celui
  # d'un Pokémon du joueur gardé actif par un Bouclier Talent) : pas de
  # message "wore off" ni de talents d'entrée relancés.
  alias __bsim_ng_pbAbilitiesOnNeutralizingGasEnding pbAbilitiesOnNeutralizingGasEnding unless method_defined?(:__bsim_ng_pbAbilitiesOnNeutralizingGasEnding)
  def pbAbilitiesOnNeutralizingGasEnding
    if BattleModifiers.active? && BattleModifiers.enabled?(:aura_neutralizing_gas) &&
       (BattleModifiers.ai_battler?(self) || self.item != :ABILITYSHIELD)
      return
    end
    return __bsim_ng_pbAbilitiesOnNeutralizingGasEnding
  end
end

#-------------------------------------------------------------------------------
# Fantômasque : le 1er coup reçu par chaque Pokémon de l'IA ne fait aucun
# dégât (Clone et Brise Moule passent outre), puis le Pokémon perd 1/8 de ses
# PV. Un Pokémon dont le déguisement est tombé le reste tout le combat.
#-------------------------------------------------------------------------------
BattleModifiers.get(:aura_disguise).tap do |m|
  m.on(:damage_absorption) do |user, target, move|
    battle = target.battle
    next if !BattleSimulator::BossAuras.can_absorb?(battle, target, :DISGUISE, user)
    next if BattleSimulator::BossAuras.broken?(:aura_disguise_broken, target)
    target.damageState.disguise = true
    BattleSimulator::BossAuras.set_broken(:aura_disguise_broken, target, true)
    (BattleModifiers.state[:aura_disguise_hits] ||= {})[target.index] = true
  end
  m.on(:endure_ko_message) do |move, target|
    hits = BattleModifiers.state[:aura_disguise_hits]
    next nil if !hits || !hits.delete(target.index) || !target.damageState.disguise
    battle = target.battle
    BattleSimulator::BossAuras.show_splash(battle, target, :DISGUISE,
                                           _INTL("Its disguise served it as a decoy!"))
    battle.pbDisplay(_INTL("{1}'s disguise was busted!", target.pbThis))
    # Garde Magik (vrai talent ou aura) bloque ces dégâts, comme dans Showdown.
    if Settings::MECHANICS_GENERATION >= 8 && target.takesIndirectDamage?
      target.pbReduceHP(target.totalhp / 8, false)
    end
    target.bmod_clear_shown_ability   # Garde Magik virtuelle testée sans bulle
    next true
  end
end

#-------------------------------------------------------------------------------
# Tête de Gel : le 1er coup PHYSIQUE reçu par chaque Pokémon de l'IA ne fait
# aucun dégât. Comme pour Bekaglaçon, elle se reforme quand la grêle commence
# (en fin de tour) ou quand le Pokémon entre en jeu sous la grêle.
#-------------------------------------------------------------------------------
BattleModifiers.get(:aura_ice_face).tap do |m|
  m.on(:damage_absorption) do |user, target, move|
    battle = target.battle
    next if !move.physicalMove?
    next if !BattleSimulator::BossAuras.can_absorb?(battle, target, :ICEFACE, user)
    next if BattleSimulator::BossAuras.broken?(:aura_ice_face_broken, target)
    target.damageState.iceFace = true
    BattleSimulator::BossAuras.set_broken(:aura_ice_face_broken, target, true)
    (BattleModifiers.state[:aura_ice_face_hits] ||= {})[target.index] = true
  end
  m.on(:endure_ko_message) do |move, target|
    hits = BattleModifiers.state[:aura_ice_face_hits]
    next nil if !hits || !hits.delete(target.index) || !target.damageState.iceFace
    BattleSimulator::BossAuras.show_splash(target.battle, target, :ICEFACE,
      _INTL("{1}'s Ice Face took the hit and broke!", target.pbThis))
    next true
  end
  # La grêle commence (et touche ce Pokémon) : sa Tête de Gel brisée se
  # reformera en fin de tour, comme le canRestoreIceFace de Bekaglaçon. Les
  # Pokémon au banc sont gérés par on_battler_enter.
  m.on(:on_weather_change) do |battle, old_weather, new_weather|
    next if new_weather != :Hail
    broken  = BattleModifiers.state[:aura_ice_face_broken] || {}
    restore = (BattleModifiers.state[:aura_ice_face_restore] ||= {})
    BattleModifiers::Tools.ai_battlers(battle).each do |b|
      key = BattleSimulator::BossAuras.pokemon_key(b)
      restore[key] = true if broken[key] && b.effectiveWeather == :Hail
    end
  end
  m.on(:on_end_of_round) do |battle|
    restore = BattleModifiers.state[:aura_ice_face_restore]
    next if !restore || restore.empty?
    BattleModifiers::Tools.ai_battlers(battle).each do |b|
      next if !restore[BattleSimulator::BossAuras.pokemon_key(b)]
      next if b.effectiveWeather != :Hail
      BattleSimulator::BossAuras.restore_ice_face(battle, b)
    end
    restore.clear   # Valable pour ce tour seulement
  end
  m.on(:on_battler_enter) do |battle, battler|
    next if !BattleModifiers.ai_battler?(battler) || battler.effectiveWeather != :Hail
    BattleSimulator::BossAuras.restore_ice_face(battle, battler)
  end
end

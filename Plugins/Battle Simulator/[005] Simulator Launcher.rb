#===============================================================================
# Battle Simulator - démarrage du jeu et lancement des combats.
#
# 1. pbCallTitle renvoie Scene_BattleSimulatorBoot au lieu de l'écran titre.
# 2. Celle-ci crée une partie neuve en silence (Game.start_new), comme "Nouvelle
#    partie", puis demande l'ouverture du menu.
# 3. Au premier rafraîchissement de Scene_Map (avant tout événement de la carte,
#    donc l'intro de la carte de départ ne se lance jamais), la boucle du
#    simulateur prend la main : menu -> combat -> menu...
#
# Les combats passent par TrainerBattle.start_core, exactement comme un combat
# de dresseur normal : l'EBDX, le Gen 9 Pack et les autres plugins
# fonctionnent sans adaptation.
#===============================================================================
class Game_Temp
  attr_accessor :bsim_open_menu
end

module BattleSimulator
  OUTCOME_NAMES = {
    0 => _INTL("Annulé"),
    1 => _INTL("Victoire"),
    2 => _INTL("Défaite"),
    3 => _INTL("Abandon"),
    5 => _INTL("Égalité")
  }

  @in_battle = false

  module_function

  def in_battle?
    return @in_battle
  end

  # Ouvrir le simulateur au démarrage ? (CTRL maintenu = jeu normal)
  def boot_into_simulator?
    return false if !BattleSimulator::ENABLED
    Input.update
    return !Input.press?(Input::CTRL)
  end

  # Équivalent silencieux de "Nouvelle partie".
  def start_new_game
    Game.start_new
    $player.name = BattleSimulator::PLAYER_NAME
    pbChangePlayer(BattleSimulator::PLAYER_CHARACTER_ID)
    if BattleSimulator::ALLOW_MEGA_EVOLUTION && GameData::Item.exists?(:MEGARING)
      $bag.add(:MEGARING)
    end
    $game_temp.bsim_open_menu = true
  end

  # Boucle principale : menu -> combat -> menu... jusqu'à "Quitter le jeu".
  def main_loop
    state = MenuState.load
    loop do
      action = MenuScene.new(state).main
      if action == :quit
        $scene = nil
        return
      end
      outcome = launch_battle(state)
      state.last_result = OUTCOME_NAMES[outcome] || outcome.to_s if outcome
    end
  end

  #=============================================================================
  # Combat
  #=============================================================================
  # Construit les équipes, lance le combat et renvoie son résultat (nil si le
  # combat n'a pas pu être lancé).
  def launch_battle(state)
    teams, errors = TeamLoader.load_file
    player_team = teams.find { |t| t.name == state.player_team }
    ai_team     = teams.find { |t| t.name == state.ai_team }
    errors.push(_INTL("Équipe du joueur introuvable.")) if !player_team
    errors.push(_INTL("Équipe de l'IA introuvable.")) if !ai_team
    return show_errors(errors) if !player_team || !ai_team
    # Création des Pokémon
    ai_trainer = create_ai_trainer
    begin
      player_party = TeamLoader.build_party(player_team, $player)
      ai_party     = TeamLoader.build_party(ai_team, ai_trainer)
    rescue TeamError => e
      return show_errors([e.message])
    end
    minimum = (state.format == :double) ? 2 : 1
    if player_party.length < minimum || ai_party.length < minimum
      return show_errors([_INTL("Le format Duo demande au moins 2 Pokémon dans chaque équipe.")])
    end
    ai_trainer.party = ai_party
    # Combat
    old_party = $player.party
    outcome = nil
    begin
      $player.party = player_party
      BattleModifiers.start_session(state.selected, state.format)
      @in_battle = true
      set_battle_rules(state)
      outcome = TrainerBattle.start_core(ai_trainer)
    ensure
      @in_battle = false
      BattleModifiers.end_session
      $game_temp.clear_battle_rules
      $player.party = old_party
    end
    return outcome
  end

  def create_ai_trainer
    trainer = NPCTrainer.new(BattleSimulator::AI_TRAINER_NAME, BattleSimulator::AI_TRAINER_TYPE)
    trainer.lose_text = BattleSimulator::AI_LOSE_TEXT
    if BattleSimulator::ALLOW_MEGA_EVOLUTION && GameData::Item.exists?(:MEGARING)
      trainer.items = [:MEGARING]
    end
    return trainer
  end

  def set_battle_rules(state)
    $game_temp.clear_battle_rules
    setBattleRule((state.format == :double) ? "double" : "single")
    setBattleRule("canLose")
    setBattleRule("noExp")
    setBattleRule("noMoney")
    if BattleSimulator::EBDX_BACKDROP && defined?(EliteBattle)
      EliteBattle.set(:nextBattleBack, BattleSimulator::EBDX_BACKDROP)
    end
  end

  def show_errors(errors)
    pbMessage(_INTL("Impossible de lancer le combat :\n{1}", errors.join("\n")))
    return nil
  end
end

#===============================================================================
# Combat "hors aventure" : pas de bonus de badges ni d'affection, et le joueur
# peut abandonner (Fuite) comme dans un combat en ligne.
#===============================================================================
module BattleCreationHelperMethods
  class << self
    alias __bsim_prepare_battle prepare_battle unless method_defined?(:__bsim_prepare_battle)
    def prepare_battle(battle)
      __bsim_prepare_battle(battle)
      battle.internalBattle = false if BattleSimulator.in_battle?
    end
  end
end

# Les équipes sont temporaires : pas d'évolution d'après-combat (Kingambit,
# Annihilape, Palarticho...).
alias __bsim_pbEvolutionCheck pbEvolutionCheck unless defined?(__bsim_pbEvolutionCheck)
def pbEvolutionCheck(*args)
  return if BattleSimulator.in_battle?
  return __bsim_pbEvolutionCheck(*args)
end

#===============================================================================
# Démarrage
#===============================================================================
class Scene_BattleSimulatorBoot
  def main
    Graphics.transition(0)
    BattleSimulator.start_new_game   # Game.start_new a mis $scene = Scene_Map
    Graphics.freeze
  end
end

alias __bsim_pbCallTitle pbCallTitle unless defined?(__bsim_pbCallTitle)
def pbCallTitle
  return Scene_BattleSimulatorBoot.new if BattleSimulator.boot_into_simulator?
  return __bsim_pbCallTitle
end

class Scene_Map
  alias __bsim_update update unless method_defined?(:__bsim_update)
  def update
    if $game_temp&.bsim_open_menu
      $game_temp.bsim_open_menu = false
      BattleSimulator.main_loop
      return if $scene != self
    end
    __bsim_update
  end
end

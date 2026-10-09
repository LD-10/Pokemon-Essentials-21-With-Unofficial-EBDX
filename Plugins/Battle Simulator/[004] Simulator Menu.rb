#===============================================================================
# Battle Simulator - menu de préparation du combat.
#
# Les noms de touches sont ceux de la fenêtre des touches (F1) :
# Haut/Bas          : se déplacer (les titres de catégorie sont sautés)
# Gauche/Droite     : changer le format ou l'équipe
# Use               : cocher/décocher un gimmick, valider une action
# Action            : lancer le combat depuis n'importe quelle ligne
# Back              : revenir sur "Lancer le combat"
# JumpUp / JumpDown : catégorie précédente / suivante
#===============================================================================
module BattleSimulator
  #=============================================================================
  # Réglages du menu, mémorisés dans SESSION_FILE entre deux lancements.
  #=============================================================================
  class MenuState
    attr_accessor :format, :selected, :player_team, :ai_team, :last_result

    def initialize
      @format      = :single
      @selected    = []
      @player_team = nil
      @ai_team     = nil
      @last_result = nil
    end

    def self.load
      state = self.new
      return state if !File.exist?(BattleSimulator::SESSION_FILE)
      begin
        text = File.open(BattleSimulator::SESSION_FILE, "rb") { |f| f.read }
        text.force_encoding(Encoding::UTF_8).split(/\r?\n/).each do |line|
          next if line !~ /^(\w+)=(.*)$/
          value = $2.strip
          case $1
          when "format"      then state.format = (value == "double") ? :double : :single
          when "player_team" then state.player_team = value
          when "ai_team"     then state.ai_team = value
          when "modifiers"
            state.selected = value.split(",").map { |id| id.strip.to_sym }
          end
        end
      rescue StandardError
        return self.new
      end
      state.selected.select! { |id| BattleModifiers.exists?(id) }
      return state
    end

    def save
      lines = [
        "format=#{@format}",
        "player_team=#{@player_team}",
        "ai_team=#{@ai_team}",
        "modifiers=#{@selected.join(',')}"
      ]
      File.open(BattleSimulator::SESSION_FILE, "wb") { |f| f.write(lines.join("\n") + "\n") }
    rescue StandardError
      # Dossier en lecture seule : les réglages ne seront simplement pas gardés.
    end

    def selected?(id)
      return @selected.include?(id)
    end

    # Coche/décoche un gimmick. Renvoie les gimmicks décochés automatiquement.
    def toggle(id)
      if selected?(id)
        @selected.delete(id)
        return []
      end
      removed = BattleModifiers.incompatible_with(id, @selected)
      @selected -= removed
      @selected.push(id)
      return removed
    end

    # Gimmicks cochés qui s'appliqueront avec le format choisi.
    def effective_modifiers
      return @selected.map { |id| BattleModifiers.get(id) }.compact.select { |m| m.available_in?(@format) }
    end
  end

  #=============================================================================
  # Liste du menu (une ligne = un réglage, une action, un titre ou un gimmick).
  #=============================================================================
  class Window_SimulatorMenu < Window_DrawableCommand
    HEADER_BASE    = Color.new(48, 96, 176)
    HEADER_SHADOW  = Color.new(152, 184, 232)
    VALUE_BASE     = Color.new(248, 48, 24)
    VALUE_SHADOW   = Color.new(248, 136, 128)
    ACTION_BASE    = Color.new(232, 32, 16)
    ACTION_SHADOW  = Color.new(248, 168, 160)
    DISABLED_BASE  = Color.new(168, 168, 168)
    DISABLED_SHADOW = Color.new(216, 216, 216)
    BOX_BORDER     = Color.new(72, 72, 80)
    BOX_FILL       = Color.new(248, 248, 248)
    BOX_CHECK      = Color.new(48, 168, 64)

    attr_reader :rows

    def initialize(menu, x, y, width, height, viewport)
      @menu = menu
      @rows = []
      super(x, y, width, height, viewport)
    end

    def rows=(value)
      @rows = value
      refresh
    end

    def itemCount
      return @rows.length
    end

    def drawItem(index, _count, rect)
      row = @rows[index]
      return if !row
      if row[:type] == :header
        pbDrawShadowText(self.contents, rect.x, rect.y, rect.width, rect.height,
                         "- #{row[:text]} -", HEADER_BASE, HEADER_SHADOW, 2)
        return
      end
      rect = drawCursor(index, rect)
      case row[:type]
      when :modifier then draw_modifier(row[:modifier], rect)
      when :action   then draw_text(row[:text], rect, ACTION_BASE, ACTION_SHADOW)
      when :option
        label_width = rect.width * 2 / 5
        draw_text(row[:text], Rect.new(rect.x, rect.y, label_width, rect.height),
                  self.baseColor, self.shadowColor)
        value_rect = Rect.new(rect.x + label_width, rect.y, rect.width - label_width - 4, rect.height)
        value = fit_text("< #{@menu.option_value(row[:key])} >", value_rect.width)
        pbDrawShadowText(self.contents, value_rect.x, value_rect.y, value_rect.width,
                         value_rect.height, value, VALUE_BASE, VALUE_SHADOW, 1)
      else
        draw_text(row[:text], rect, self.baseColor, self.shadowColor)
      end
    end

    def draw_modifier(mod, rect)
      state = @menu.state
      available = mod.available_in?(state.format)
      # Case à cocher
      box_y = rect.y + ((rect.height - 16) / 2)
      self.contents.fill_rect(rect.x, box_y, 16, 16, BOX_BORDER)
      self.contents.fill_rect(rect.x + 2, box_y + 2, 12, 12, BOX_FILL)
      if state.selected?(mod.id)
        self.contents.fill_rect(rect.x + 4, box_y + 4, 8, 8, (available) ? BOX_CHECK : DISABLED_BASE)
      end
      # Étiquette à droite : portée, ou format requis
      tag = (available) ? mod.scope_name : _INTL("Duo uniquement")
      tag_width = self.contents.text_size(tag).width
      base   = (available) ? self.baseColor : DISABLED_BASE
      shadow = (available) ? self.shadowColor : DISABLED_SHADOW
      name_rect = Rect.new(rect.x + 24, rect.y, rect.width - 24 - tag_width - 12, rect.height)
      draw_text(fit_text(mod.name, name_rect.width), name_rect, base, shadow)
      pbDrawShadowText(self.contents, rect.x, rect.y, rect.width - 4, rect.height, tag,
                       DISABLED_BASE, DISABLED_SHADOW, 1)
    end

    def draw_text(text, rect, base, shadow)
      pbDrawShadowText(self.contents, rect.x, rect.y, rect.width, rect.height, text, base, shadow)
    end

    # Coupe le texte avec "..." s'il dépasse la largeur donnée.
    def fit_text(text, width)
      return text if self.contents.text_size(text).width <= width
      ret = text.dup
      while ret.length > 1 && self.contents.text_size(ret + "...").width > width
        ret = ret[0...-1]
      end
      return ret + "..."
    end
  end

  #=============================================================================
  # Scène du menu. main renvoie :start (lancer le combat) ou :quit.
  #=============================================================================
  class MenuScene
    TITLE_BASE    = Color.new(248, 248, 248)
    TITLE_SHADOW  = Color.new(40, 48, 88)
    INFO_BASE     = Color.new(208, 216, 248)
    INFO_SHADOW   = Color.new(40, 48, 88)
    TOP_HEIGHT    = 44
    LIST_HEIGHT   = 192   # 5 lignes visibles ; la description garde 4 lignes

    attr_reader :state
    # Équipes construites avant de fermer le menu (voir try_start).
    attr_reader :prepared

    def initialize(state)
      @state    = state
      @action   = nil
      @prepared = nil
      @notice   = nil
      @teams    = []
      @team_errors = []
    end

    def main
      reload_teams
      start_scene
      loop do
        Graphics.update
        Input.update
        pbUpdateSpriteHash(@sprites)
        update_input
        break if @action
      end
      end_scene
      @state.save
      return @action
    end

    #---------------------------------------------------------------------------
    # Données
    #---------------------------------------------------------------------------
    def reload_teams
      TeamLoader.clear_indexes
      begin
        @teams, @team_errors = TeamLoader.load_file
      rescue StandardError => e
        @teams, @team_errors = [], [e.message]
      end
      names = @teams.map { |t| t.name }
      @state.player_team = names[0] if !names.include?(@state.player_team)
      @state.ai_team = names[1] || names[0] if !names.include?(@state.ai_team)
    end

    def team_named(name)
      return @teams.find { |t| t.name == name }
    end

    def option_value(key)
      case key
      when :format
        return (@state.format == :double) ? _INTL("Duo (2v2)") : _INTL("Solo (1v1)")
      when :player_team, :ai_team
        team = team_named(@state.send(key))
        return _INTL("aucune") if !team
        return "#{team.name} (#{team.sets.length})"
      end
      return ""
    end

    def build_rows
      rows = []
      rows.push({ :type => :option, :key => :format,      :text => _INTL("Format") })
      rows.push({ :type => :option, :key => :player_team, :text => _INTL("Équipe joueur") })
      rows.push({ :type => :option, :key => :ai_team,     :text => _INTL("Équipe IA") })
      rows.push({ :type => :action, :key => :start,       :text => _INTL("LANCER LE COMBAT") })
      category = nil
      BattleModifiers.all.each do |mod|
        next if mod.category == :demo && !BattleSimulator::SHOW_DEMO_MODIFIERS
        if mod.category != category
          category = mod.category
          rows.push({ :type => :header, :text => BattleModifiers.category_name(category) })
        end
        rows.push({ :type => :modifier, :modifier => mod })
      end
      if rows.none? { |row| row[:type] == :modifier }
        rows.push({ :type => :header, :text => _INTL("Aucun gimmick enregistré") })
      end
      rows.push({ :type => :header, :text => _INTL("Outils") })
      rows.push({ :type => :command, :key => :clear,  :text => _INTL("Tout décocher") })
      rows.push({ :type => :command, :key => :reload, :text => _INTL("Recharger les équipes") })
      rows.push({ :type => :command, :key => :quit,   :text => _INTL("Quitter le jeu") })
      return rows
    end

    def selectable?(index)
      row = @sprites["list"].rows[index]
      return row && row[:type] != :header
    end

    def current_row
      return @sprites["list"].rows[@sprites["list"].index]
    end

    #---------------------------------------------------------------------------
    # Affichage
    #---------------------------------------------------------------------------
    def start_scene
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99_900
      @sprites = {}
      @sprites["bg"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
      draw_background(@sprites["bg"].bitmap)
      @sprites["top"] = BitmapSprite.new(Graphics.width, TOP_HEIGHT, @viewport)
      @sprites["list"] = Window_SimulatorMenu.new(self, 0, TOP_HEIGHT, Graphics.width, LIST_HEIGHT, @viewport)
      # Fenêtre active (pour ses flèches de défilement) mais les touches sont
      # gérées par la scène, qui saute les titres de catégorie.
      @sprites["list"].active = true
      @sprites["list"].ignore_input = true
      @sprites["list"].rows = build_rows
      desc_y = TOP_HEIGHT + LIST_HEIGHT
      @sprites["desc"] = Window_AdvancedTextPokemon.newWithSize(
        "", 0, desc_y, Graphics.width, Graphics.height - desc_y, @viewport
      )
      @sprites["list"].index = @sprites["list"].rows.index { |row| row[:key] == :start } || 0
      @sprites["list"].top_row = 0   # Garder "Format" visible à l'ouverture
      refresh
      play_menu_bgm
      pbFadeInAndShow(@sprites) { pbUpdateSpriteHash(@sprites) }
    end

    def end_scene
      pbFadeOutAndHide(@sprites) { pbUpdateSpriteHash(@sprites) }
      pbDisposeSpriteHash(@sprites)
      @viewport.dispose
    end

    def play_menu_bgm
      bgm = BattleSimulator::MENU_BGM || $data_system&.title_bgm
      return if !bgm
      name = (bgm.is_a?(String)) ? bgm : bgm.name
      playing = $game_system&.getPlayingBGM
      return if playing && playing.name == name   # Ne pas relancer la piste en cours
      pbBGMPlay(bgm)
    end

    def draw_background(bitmap)
      height = bitmap.height
      height.times do |y|
        ratio = y.to_f / height
        color = Color.new(32 - (20 * ratio), 44 - (28 * ratio), 88 - (56 * ratio))
        bitmap.fill_rect(0, y, bitmap.width, 1, color)
      end
    end

    def refresh
      refresh_top
      @sprites["list"].refresh
      @sprites["desc"].text = description_text
    end

    def refresh_top
      bitmap = @sprites["top"].bitmap
      bitmap.clear
      pbSetSystemFont(bitmap)
      pbDrawTextPositions(bitmap, [
        [_INTL("BATTLE SIMULATOR"), 12, 8, :left, TITLE_BASE, TITLE_SHADOW]
      ])
      pbSetSmallFont(bitmap)
      count = @state.effective_modifiers.length
      line1 = _INTL("{1} | {2} gimmick(s) actif(s)", option_value(:format), count)
      line2 = ""
      line2 = _INTL("Dernier combat : {1}", @state.last_result) if @state.last_result
      line2 = @notice if @notice
      pbDrawTextPositions(bitmap, [
        [line1, Graphics.width - 12, 4, :right, INFO_BASE, INFO_SHADOW],
        [line2, Graphics.width - 12, 22, :right, INFO_BASE, INFO_SHADOW]
      ])
    end

    def description_text
      row = current_row
      return "" if !row
      case row[:type]
      when :modifier
        mod = row[:modifier]
        text = mod.description.dup
        info = [_INTL("Portée : {1}", mod.scope_name)]
        info.push(_INTL("Duo uniquement")) if !mod.available_in?(:single)
        info.push(_INTL("Solo uniquement")) if !mod.available_in?(:double)
        text += "\n" + info.join("   ")
        return text
      when :option
        case row[:key]
        when :format
          return _INTL("Gauche/Droite : Solo (1 Pokémon de chaque côté) ou Duo (2 contre 2).")
        else
          return _INTL("Gauche/Droite : choisir une équipe de {1}.", BattleSimulator::TEAMS_FILE) if @team_errors.empty?
          return _INTL("Erreurs dans {1} :\n{2}", BattleSimulator::TEAMS_FILE, @team_errors.first(2).join("\n"))
        end
      when :action
        mods = @state.effective_modifiers.map { |m| m.name }
        text = _INTL("{1} contre {2}.", option_value(:player_team), option_value(:ai_team))
        text += "\n" + ((mods.empty?) ? _INTL("Aucun gimmick.") : _INTL("Gimmicks : {1}", mods.join(", ")))
        return text
      when :command
        case row[:key]
        when :clear  then return _INTL("Décoche tous les gimmicks.")
        when :reload then return _INTL("Relit {1} après une modification.", BattleSimulator::TEAMS_FILE)
        when :quit   then return _INTL("Ferme le jeu.")
        end
      end
      return ""
    end

    #---------------------------------------------------------------------------
    # Entrées
    #---------------------------------------------------------------------------
    def update_input
      if Input.repeat?(Input::UP)
        move_cursor(-1)
      elsif Input.repeat?(Input::DOWN)
        move_cursor(1)
      elsif Input.repeat?(Input::LEFT)
        change_option(-1)
      elsif Input.repeat?(Input::RIGHT)
        change_option(1)
      elsif Input.trigger?(Input::JUMPUP) || Input.trigger?(Input::AUX1)
        jump_category(-1)
      elsif Input.trigger?(Input::JUMPDOWN) || Input.trigger?(Input::AUX2)
        jump_category(1)
      elsif Input.trigger?(Input::ACTION)
        try_start
      elsif Input.trigger?(Input::BACK)
        start_index = @sprites["list"].rows.index { |row| row[:key] == :start }
        if start_index && @sprites["list"].index != start_index
          pbPlayCancelSE
          set_index(start_index)
        end
      elsif Input.trigger?(Input::USE)
        activate_row
      end
    end

    def set_index(index)
      @notice = nil
      refresh_top
      @sprites["list"].index = index
      @sprites["list"].refresh
      @sprites["desc"].text = description_text
    end

    def move_cursor(dir)
      rows = @sprites["list"].rows
      index = @sprites["list"].index
      rows.length.times do
        index = (index + dir) % rows.length
        break if selectable?(index)
      end
      return if index == @sprites["list"].index
      pbPlayCursorSE
      set_index(index)
    end

    def jump_category(dir)
      rows = @sprites["list"].rows
      headers = []
      rows.each_with_index { |row, i| headers.push(i) if row[:type] == :header }
      return if headers.empty?
      index = @sprites["list"].index
      if dir > 0
        target = headers.find { |h| h > index }
        target ||= -1
      else
        current = headers.reverse.find { |h| h < index }
        target = headers.reverse.find { |h| current && h < current }
        target ||= -1
      end
      new_index = target + 1
      new_index += 1 while new_index < rows.length && !selectable?(new_index)
      return if new_index >= rows.length || new_index == index
      pbPlayCursorSE
      set_index(new_index)
    end

    def change_option(dir)
      row = current_row
      return if !row || row[:type] != :option
      case row[:key]
      when :format
        @state.format = (@state.format == :double) ? :single : :double
      when :player_team, :ai_team
        return pbPlayBuzzerSE if @teams.length < 2
        names = @teams.map { |t| t.name }
        index = names.index(@state.send(row[:key])) || 0
        @state.send("#{row[:key]}=", names[(index + dir) % names.length])
      end
      pbPlayCursorSE
      refresh
    end

    # Construit les équipes avant de fermer le menu : en cas d'erreur, le
    # message s'affiche par-dessus le menu et on y reste.
    def try_start
      prepared, errors = BattleSimulator.prepare_battle(@state)
      if !prepared
        pbPlayBuzzerSE
        pbMessage(_INTL("Impossible de lancer le combat :\n{1}", errors.join("\n")))
        return
      end
      pbPlayDecisionSE
      @prepared = prepared
      @action = :start
    end

    def activate_row
      row = current_row
      return if !row
      case row[:type]
      when :modifier
        removed = @state.toggle(row[:modifier].id)
        pbPlayDecisionSE
        if !removed.empty?
          names = removed.map { |id| BattleModifiers.get(id).name }
          @notice = _INTL("Décoché : {1}", names.join(", "))
        end
        refresh
      when :option
        change_option(1)
      when :action
        try_start
      when :command
        case row[:key]
        when :clear
          @state.selected.clear
          pbPlayDecisionSE
          refresh
        when :reload
          reload_teams
          pbPlayDecisionSE
          refresh
          if !@team_errors.empty?
            pbMessage(_INTL("Erreurs dans {1} :\n{2}", BattleSimulator::TEAMS_FILE, @team_errors.join("\n")))
          end
        when :quit
          @action = :quit if pbConfirmMessage(_INTL("Quitter le jeu ?"))
        end
      end
    end
  end
end

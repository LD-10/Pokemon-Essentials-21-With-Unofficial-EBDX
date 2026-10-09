#===============================================================================
# Battle Simulator - éditeur d'équipes en jeu.
#
# Depuis le menu : Entrée sur "Équipe joueur" ou "Équipe IA" modifie l'équipe
# choisie ; "Créer une équipe" (Outils) en crée une nouvelle. Les changements
# sont écrits dans BattleSimulator::TEAMS_FILE au format Showdown : seule
# l'équipe modifiée est réécrite, le reste du fichier (autres équipes,
# commentaires) est conservé tel quel.
#===============================================================================
module BattleSimulator
  #=============================================================================
  # Conversion Pokemon -> texte Showdown, et mise à jour du fichier d'équipes.
  #=============================================================================
  module TeamWriter
    STAT_LABELS = {
      :HP => "HP", :ATTACK => "Atk", :DEFENSE => "Def",
      :SPECIAL_ATTACK => "SpA", :SPECIAL_DEFENSE => "SpD", :SPEED => "Spe"
    }

    module_function

    # Lignes Showdown d'un Pokémon (noms anglais du jeu, relus par TeamLoader).
    def pokemon_lines(pkmn)
      species = GameData::Species.get(pkmn.species)
      header = species.real_name
      header = "#{pkmn.name} (#{species.real_name})" if pkmn.nicknamed? && pkmn.name != species.real_name
      header += (pkmn.male?) ? " (M)" : " (F)" if !pkmn.singleGendered? && !pkmn.genderless?
      header += " @ #{GameData::Item.get(pkmn.item_id).real_name}" if pkmn.item_id
      lines = [header]
      lines.push("Ability: #{GameData::Ability.get(pkmn.ability_id).real_name}") if pkmn.ability_id
      lines.push("Level: #{pkmn.level}")
      lines.push("Form: #{pkmn.form_simple}") if pkmn.form_simple != 0
      lines.push("Shiny: Yes") if pkmn.shiny?
      lines.push("Happiness: #{pkmn.happiness}") if pkmn.happiness != 255
      lines.push("Ball: #{GameData::Item.get(pkmn.poke_ball).real_name}") if pkmn.poke_ball && pkmn.poke_ball != :POKEBALL
      evs = STAT_LABELS.map { |stat, label| (pkmn.ev[stat] > 0) ? "#{pkmn.ev[stat]} #{label}" : nil }.compact
      lines.push("EVs: #{evs.join(' / ')}") if !evs.empty?
      lines.push("#{GameData::Nature.get(pkmn.nature.id).real_name} Nature") if pkmn.nature
      ivs = STAT_LABELS.map { |stat, label| (pkmn.iv[stat] != Pokemon::IV_STAT_LIMIT) ? "#{pkmn.iv[stat]} #{label}" : nil }.compact
      lines.push("IVs: #{ivs.join(' / ')}") if !ivs.empty?
      pkmn.moves.each { |m| lines.push("- #{GameData::Move.get(m.id).real_name}") }
      return lines
    end

    def team_lines(name, party, format_tag = "gen9")
      lines = [(format_tag && !format_tag.empty?) ? "=== [#{format_tag}] #{name} ===" : "=== #{name} ==="]
      party.each do |pkmn|
        lines.push("")
        lines.concat(pokemon_lines(pkmn))
      end
      return lines
    end

    def read_lines(path = BattleSimulator::TEAMS_FILE)
      return [[], "\n"] if !File.exist?(path)
      text = TeamLoader.decode_text(File.open(path, "rb") { |f| f.read })
      newline = (text.include?("\r\n")) ? "\r\n" : "\n"
      return [text.split(/\r?\n/, -1), newline]
    end

    def write_lines(lines, newline, path = BattleSimulator::TEAMS_FILE)
      lines = lines.dup
      lines.pop while !lines.empty? && lines.last.strip.empty?
      File.open(path, "wb") { |f| f.write(lines.join(newline) + newline) }
    end

    # Remplace l'équipe old_team (lue dans le fichier) par une nouvelle version,
    # ou l'ajoute à la fin si old_team est nil.
    def save_team(old_team, name, party, format_tag = "gen9", path = BattleSimulator::TEAMS_FILE)
      lines, newline = read_lines(path)
      block = team_lines(name, party, format_tag)
      if old_team && old_team.start_line && old_team.end_line && old_team.end_line < lines.length
        lines[old_team.start_line..old_team.end_line] = block
      else
        lines.pop while !lines.empty? && lines.last.strip.empty?
        lines.push("") if !lines.empty?
        lines.concat(block)
      end
      write_lines(lines, newline, path)
    end

    def delete_team(old_team, path = BattleSimulator::TEAMS_FILE)
      return if !old_team || !old_team.start_line || !old_team.end_line
      lines, newline = read_lines(path)
      return if old_team.end_line >= lines.length
      last = old_team.end_line
      last += 1 while last + 1 < lines.length && lines[last + 1].strip.empty?   # Lignes vides qui suivent
      lines[old_team.start_line..last] = []
      write_lines(lines, newline, path)
    end

    # Nom libre (les équipes sont retrouvées par leur nom).
    def unique_name(base, existing)
      return base if !existing.include?(base)
      n = 2
      n += 1 while existing.include?("#{base} (#{n})")
      return "#{base} (#{n})"
    end
  end

  #=============================================================================
  # Écran générique : liste à gauche, détails à droite.
  #=============================================================================
  class ListInfoScreen
    TITLE_BASE   = Color.new(248, 248, 248)
    TITLE_SHADOW = Color.new(40, 48, 88)
    TOP_HEIGHT   = 36

    # commands_proc renvoie la liste des lignes ; info_proc(index) le texte de
    # droite pour la ligne sélectionnée.
    def initialize(title, commands_proc, info_proc)
      @title         = title
      @commands_proc = commands_proc
      @info_proc     = info_proc
    end

    def title=(value)
      @title = value
      draw_title if @sprites
    end

    def start
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99_000
      @sprites = {}
      @sprites["bg"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
      @sprites["bg"].bitmap.fill_rect(0, 0, Graphics.width, Graphics.height, Color.new(16, 24, 48))
      @sprites["top"] = BitmapSprite.new(Graphics.width, TOP_HEIGHT, @viewport)
      list_width = Graphics.width / 2
      @sprites["list"] = Window_CommandPokemon.newWithSize(
        @commands_proc.call, 0, TOP_HEIGHT, list_width, Graphics.height - TOP_HEIGHT, @viewport
      )
      @sprites["info"] = Window_AdvancedTextPokemon.newWithSize(
        "", list_width, TOP_HEIGHT, Graphics.width - list_width, Graphics.height - TOP_HEIGHT, @viewport
      )
      draw_title
      refresh
      pbFadeInAndShow(@sprites) { pbUpdateSpriteHash(@sprites) }
    end

    def finish
      pbFadeOutAndHide(@sprites) { pbUpdateSpriteHash(@sprites) }
      pbDisposeSpriteHash(@sprites)
      @viewport.dispose
      @sprites = nil
    end

    def draw_title
      bitmap = @sprites["top"].bitmap
      bitmap.clear
      pbSetSystemFont(bitmap)
      text = BattleSimulator.fit_text(bitmap, @title, Graphics.width - 24)
      pbDrawTextPositions(bitmap, [[text, 12, 4, :left, TITLE_BASE, TITLE_SHADOW]])
    end

    # Relit la liste (après une modification) en gardant la position.
    def refresh(index = nil)
      list = @sprites["list"]
      list.commands = @commands_proc.call
      list.index = [[index || list.index, list.commands.length - 1].min, 0].max
      @last_index = nil
      update_info
    end

    def update_info
      return if @last_index == @sprites["list"].index
      @last_index = @sprites["list"].index
      @sprites["info"].text = @info_proc.call(@last_index) || ""
    end

    # Attend un choix : renvoie l'index ou -1 (Retour).
    def choose
      loop do
        Graphics.update
        Input.update
        pbUpdateSpriteHash(@sprites)
        update_info
        if Input.trigger?(Input::BACK)
          pbPlayCancelSE
          return -1
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          return @sprites["list"].index
        end
      end
    end
  end

  #=============================================================================
  # Éditeur d'une équipe.
  #=============================================================================
  class TeamEditor
    # Renvoie le nom sous lequel l'équipe a été enregistrée, :deleted si elle
    # a été supprimée, ou nil si rien n'a été enregistré.
    def self.edit(team_name)
      teams, = TeamLoader.load_file
      team = teams.find { |t| t.name == team_name }
      return nil if !team
      return self.new(team, teams.map { |t| t.name }).run
    end

    def self.create
      teams, = TeamLoader.load_file
      names = teams.map { |t| t.name }
      name = TeamWriter.unique_name(_INTL("Nouvelle équipe"), names)
      return self.new(nil, names, name).run
    end

    def initialize(team, all_names, new_name = nil)
      @team      = team                       # nil = nouvelle équipe
      @all_names = all_names
      @name      = (team) ? team.name : new_name
      @tag       = (team && team.format_tag) ? team.format_tag : "gen9"
      @party     = []
      @dropped   = []
      @changed   = (team.nil?)
      return if !team
      team.sets.each_with_index do |set, i|
        break if @party.length >= Settings::MAX_PARTY_SIZE
        begin
          @party.push(TeamLoader.build_pokemon(set, $player))
        rescue TeamError => e
          @dropped.push(_INTL("{1}, ligne {2} : {3}", set.label, set.line_no, e.message))
        end
      end
    end

    def run
      @screen = ListInfoScreen.new(title, method(:team_commands), method(:team_info))
      @screen.start
      if !@dropped.empty?
        pbMessage(_INTL("Ces Pokémon contiennent des erreurs et seront retirés si vous enregistrez :\n{1}",
                        @dropped.join("\n")))
      end
      result = nil
      loop do
        index = @screen.choose
        action = (index < 0) ? :leave : row_action(index)
        case action
        when :pokemon
          pokemon_menu(index)
        when :add
          add_pokemon
        when :rename
          rename
        when :save
          result = save
          break if result
        when :duplicate
          if @party.empty?
            pbMessage(_INTL("L'équipe est vide."))
          else
            new_name = TeamWriter.unique_name(_INTL("{1} (copie)", @name), @all_names)
            TeamWriter.save_team(nil, new_name, @party, @tag)
            @all_names.push(new_name)
            pbMessage(_INTL("Copie enregistrée sous le nom \"{1}\".", new_name))
          end
        when :delete
          if @team && pbConfirmMessageSerious(_INTL("Supprimer définitivement l'équipe \"{1}\" ?", @name))
            TeamWriter.delete_team(@team)
            result = :deleted
            break
          end
        when :leave
          break if !@changed || pbConfirmMessage(_INTL("Quitter sans enregistrer les modifications ?"))
        end
        @screen.title = title
        @screen.refresh
      end
      @screen.finish
      return result
    end

    def title
      return _INTL("Équipe : {1}{2}", @name, (@changed) ? " *" : "")
    end

    #---------------------------------------------------------------------------
    # Liste de l'équipe
    #---------------------------------------------------------------------------
    def rows
      ret = []
      @party.each_index { |i| ret.push(:pokemon) }
      ret.push(:add) if @party.length < Settings::MAX_PARTY_SIZE
      ret.push(:rename, :save, :duplicate)
      ret.push(:delete) if @team
      ret.push(:leave)
      return ret
    end

    def row_action(index)
      return rows[index]
    end

    def team_commands
      ret = []
      @party.each_with_index do |pkmn, i|
        ret.push(_INTL("{1}. {2} Nv.{3}", i + 1, pkmn.name, pkmn.level))
      end
      rows[@party.length..-1].each do |row|
        case row
        when :add       then ret.push(_INTL("+ Ajouter un Pokémon"))
        when :rename    then ret.push(_INTL("Renommer l'équipe"))
        when :save      then ret.push(_INTL("Enregistrer"))
        when :duplicate then ret.push(_INTL("Enregistrer une copie"))
        when :delete    then ret.push(_INTL("Supprimer l'équipe"))
        when :leave     then ret.push(_INTL("Retour"))
        end
      end
      return ret
    end

    def team_info(index)
      return PokemonEditor.summary(@party[index]) if index < @party.length
      case rows[index]
      when :add    then return _INTL("Ajoute un Pokémon (6 au maximum).")
      when :rename then return _INTL("Change le nom de l'équipe.")
      when :save   then return _INTL("Écrit l'équipe dans {1}.", BattleSimulator::TEAMS_FILE)
      when :duplicate then return _INTL("Enregistre l'équipe sous un nouveau nom, sans toucher à l'originale.")
      when :delete then return _INTL("Supprime l'équipe du fichier.")
      when :leave  then return _INTL("Revient au menu.")
      end
      return ""
    end

    def pokemon_menu(index)
      pkmn = @party[index]
      commands = [_INTL("Modifier"), _INTL("Résumé"), _INTL("Monter"), _INTL("Descendre"),
                  _INTL("Dupliquer"), _INTL("Retirer"), _INTL("Annuler")]
      case pbMessage(_INTL("{1} : que faire ?", pkmn.name), commands, commands.length)
      when 0
        @changed = true if PokemonEditor.new(pkmn).run
      when 1
        pbFadeOutIn do
          scene = PokemonSummary_Scene.new
          PokemonSummaryScreen.new(scene).pbStartScreen(@party, index)
        end
      when 2
        return if index == 0
        @party[index - 1], @party[index] = @party[index], @party[index - 1]
        @changed = true
        @screen.refresh(index - 1)
      when 3
        return if index >= @party.length - 1
        @party[index + 1], @party[index] = @party[index], @party[index + 1]
        @changed = true
        @screen.refresh(index + 1)
      when 4
        if @party.length >= Settings::MAX_PARTY_SIZE
          pbMessage(_INTL("L'équipe est déjà complète."))
        else
          @party.insert(index + 1, pkmn.clone_for_editor)
          @changed = true
        end
      when 5
        if pbConfirmMessage(_INTL("Retirer {1} de l'équipe ?", pkmn.name))
          @party.delete_at(index)
          @changed = true
        end
      end
    end

    def add_pokemon
      species = PokemonEditor.choose_data(GameData::Species, _INTL("Quelle espèce ?"))
      return if !species
      params = ChooseNumberParams.new
      params.setRange(1, GameData::GrowthRate.max_level)
      params.setDefaultValue(BattleSimulator::DEFAULT_LEVEL)
      params.setCancelValue(0)
      level = pbMessageChooseNumber(_INTL("Niveau ?"), params)
      return if level <= 0
      pkmn = Pokemon.new(species, level, $player)
      pkmn.shiny = false
      pkmn.ability_index = 0
      pkmn.nature = :HARDY
      pkmn.happiness = 255
      GameData::Stat.each_main { |s| pkmn.iv[s.id] = Pokemon::IV_STAT_LIMIT; pkmn.ev[s.id] = 0 }
      pkmn.calc_stats
      @party.push(pkmn)
      @changed = true
      PokemonEditor.new(pkmn).run
    end

    def rename
      new_name = pbEnterText(_INTL("Nom de l'équipe ?"), 1, 40, @name)
      new_name = new_name.to_s.strip.gsub("=", "")
      return if new_name.empty? || new_name == @name
      if (@all_names - [@team&.name]).include?(new_name)
        pbMessage(_INTL("Une autre équipe porte déjà ce nom."))
        return
      end
      @name = new_name
      @changed = true
    end

    def save
      if @party.empty?
        pbMessage(_INTL("Ajoutez au moins un Pokémon avant d'enregistrer."))
        return nil
      end
      begin
        TeamWriter.save_team(@team, @name, @party, @tag)
      rescue StandardError => e
        pbMessage(_INTL("Impossible d'écrire {1} :\n{2}", BattleSimulator::TEAMS_FILE, e.message))
        return nil
      end
      pbMessage(_INTL("Équipe \"{1}\" enregistrée.", @name))
      return @name
    end
  end

  #=============================================================================
  # Éditeur d'un Pokémon (champs en français, recherche par nom).
  #=============================================================================
  class PokemonEditor
    FIELDS = [:species, :form, :level, :item, :ability, :nature,
              :move0, :move1, :move2, :move3, :evs, :ivs,
              :gender, :shiny, :nickname, :advanced, :done]

    def self.data_name(data_class, id)
      return _INTL("(aucun)") if !id
      data = data_class.try_get(id)
      return (data) ? data.name : id.to_s
    end

    def self.summary(pkmn)
      return "" if !pkmn
      lines = []
      form = pkmn.species_data.form_name
      lines.push((form && !form.empty?) ? "#{pkmn.speciesName} (#{form})" : pkmn.speciesName)
      lines.push(_INTL("Nv. {1}  {2}", pkmn.level, data_name(GameData::Item, pkmn.item_id)))
      lines.push(_INTL("Talent : {1}", data_name(GameData::Ability, pkmn.ability_id)))
      lines.push(_INTL("Nature : {1}", pkmn.nature&.name))
      lines.push(_INTL("PV {1} / Atq {2} / Déf {3}", pkmn.totalhp, pkmn.attack, pkmn.defense))
      lines.push(_INTL("AtqS {1} / DéfS {2} / Vit {3}", pkmn.spatk, pkmn.spdef, pkmn.speed))
      pkmn.moves.each { |m| lines.push("- #{m.name}") }
      return lines.join("\n")
    end

    # Choix d'une donnée (espèce, objet, talent, attaque) : recherche par nom
    # ou liste complète. Renvoie l'ID choisi ou nil.
    def self.choose_data(data_class, prompt, default = nil)
      case pbMessage(prompt, [_INTL("Rechercher par nom"), _INTL("Liste complète"), _INTL("Annuler")], 3)
      when 0
        text = pbEnterText(prompt, 0, 24)
        key = TeamLoader.normalize(text)
        return nil if key.empty?
        matches = []
        data_class.each do |data|
          next if data.respond_to?(:form) && data.form != 0
          names = [data.real_name, data.name, data.id.to_s].map { |n| TeamLoader.normalize(n) }
          next if names.none? { |n| n.include?(key) }
          exact = names.include?(key)
          matches.push([exact ? 0 : 1, data.name, data.id])
        end
        if matches.empty?
          pbMessage(_INTL("Aucun résultat pour \"{1}\".", text))
          return nil
        end
        exact = matches.select { |m| m[0] == 0 }
        return exact[0][2] if exact.length == 1
        commands = matches.sort_by { |m| [m[0], m[1]] }.each_with_index.map { |m, i| [i + 1, m[1], m[2]] }
        return pbChooseList(commands, default, nil, -1)
      when 1
        return pbChooseFromGameDataList(data_class.name.split("::").last.to_sym, default) do |data|
          next (data.respond_to?(:form) && data.form > 0) ? nil : data.name
        end
      end
      return nil
    end

    def initialize(pkmn)
      @pkmn    = pkmn
      @changed = false
    end

    # Renvoie true si le Pokémon a été modifié.
    def run
      screen = ListInfoScreen.new(_INTL("Modifier : {1}", @pkmn.name), method(:commands),
                                  proc { |_i| PokemonEditor.summary(@pkmn) })
      screen.start
      loop do
        index = screen.choose
        field = (index < 0) ? :done : FIELDS[index]
        break if field == :done
        edit(field)
        @pkmn.calc_stats
        screen.title = _INTL("Modifier : {1}", @pkmn.name)
        screen.refresh
      end
      screen.finish
      return @changed
    end

    def commands
      pkmn = @pkmn
      form = pkmn.species_data.form_name
      ret = []
      FIELDS.each do |field|
        case field
        when :species  then ret.push(_INTL("Espèce : {1}", pkmn.speciesName))
        when :form     then ret.push(_INTL("Forme : {1}", (form && !form.empty?) ? form : pkmn.form_simple.to_s))
        when :level    then ret.push(_INTL("Niveau : {1}", pkmn.level))
        when :item     then ret.push(_INTL("Objet : {1}", PokemonEditor.data_name(GameData::Item, pkmn.item_id)))
        when :ability  then ret.push(_INTL("Talent : {1}", PokemonEditor.data_name(GameData::Ability, pkmn.ability_id)))
        when :nature   then ret.push(_INTL("Nature : {1}", pkmn.nature&.name))
        when :move0, :move1, :move2, :move3
          m = pkmn.moves[field.to_s[-1].to_i]
          ret.push(_INTL("Attaque {1} : {2}", field.to_s[-1].to_i + 1, (m) ? m.name : "-"))
        when :evs      then ret.push(_INTL("EV : {1}", stat_line(pkmn.ev)))
        when :ivs      then ret.push(_INTL("IV : {1}", stat_line(pkmn.iv)))
        when :gender
          g = (pkmn.genderless?) ? _INTL("aucun") : (pkmn.male?) ? _INTL("Mâle") : _INTL("Femelle")
          ret.push(_INTL("Sexe : {1}", g))
        when :shiny    then ret.push(_INTL("Chromatique : {1}", (pkmn.shiny?) ? _INTL("Oui") : _INTL("Non")))
        when :nickname then ret.push(_INTL("Surnom : {1}", (pkmn.nicknamed?) ? pkmn.name : "-"))
        when :advanced then ret.push(_INTL("Éditeur avancé (Debug)"))
        when :done     then ret.push(_INTL("Terminé"))
        end
      end
      return ret
    end

    def stat_line(hash)
      return TeamWriter::STAT_LABELS.keys.map { |s| hash[s] }.join("/")
    end

    def edit(field)
      pkmn = @pkmn
      case field
      when :species
        id = PokemonEditor.choose_data(GameData::Species, _INTL("Quelle espèce ?"), pkmn.species)
        return if !id || id == pkmn.species
        pkmn.species = id
        pkmn.ability_index = 0
      when :form
        forms = []
        GameData::Species.each do |sp|
          next if sp.species != pkmn.species
          next if sp.form > 0 && (sp.mega_stone || sp.mega_move)
          name = (sp.form_name && !sp.form_name.empty?) ? sp.form_name : _INTL("Forme de base")
          forms.push([sp.form, "#{sp.form}: #{name}"])
        end
        if forms.length < 2
          pbMessage(_INTL("Cette espèce n'a pas d'autre forme."))
          return
        end
        choice = pbMessage(_INTL("Quelle forme ?"), forms.map { |f| f[1] } + [_INTL("Annuler")], forms.length + 1)
        return if choice >= forms.length
        pkmn.form_simple = forms[choice][0]
        pkmn.ability_index = pkmn.ability_index   # recalcule le talent de la forme
      when :level
        params = ChooseNumberParams.new
        params.setRange(1, GameData::GrowthRate.max_level)
        params.setDefaultValue(pkmn.level)
        params.setCancelValue(0)
        level = pbMessageChooseNumber(_INTL("Niveau ?"), params)
        return if level <= 0
        pkmn.level = level
      when :item
        case pbMessage(_INTL("Objet tenu ?"), [_INTL("Choisir un objet"), _INTL("Aucun objet"), _INTL("Annuler")], 3)
        when 0
          id = PokemonEditor.choose_data(GameData::Item, _INTL("Quel objet ?"), pkmn.item_id)
          return if !id
          pkmn.item = id
        when 1
          pkmn.item = nil
        else
          return
        end
      when :ability
        sp = pkmn.species_data
        own = (sp.abilities + sp.hidden_abilities).uniq
        cmds = own.map { |a| GameData::Ability.get(a).name } + [_INTL("Autre talent..."), _INTL("Annuler")]
        choice = pbMessage(_INTL("Quel talent ?"), cmds, cmds.length)
        if choice < own.length
          pkmn.ability = own[choice]
        elsif choice == own.length
          id = PokemonEditor.choose_data(GameData::Ability, _INTL("Quel talent ?"), pkmn.ability_id)
          return if !id
          pkmn.ability = id
        else
          return
        end
      when :nature
        natures = []
        GameData::Nature.each do |n|
          ups   = n.stat_changes.select { |c| c[1] > 0 }.map { |c| GameData::Stat.get(c[0]).name_brief }
          downs = n.stat_changes.select { |c| c[1] < 0 }.map { |c| GameData::Stat.get(c[0]).name_brief }
          label = (ups.empty?) ? n.name : "#{n.name} (+#{ups.join(',')} -#{downs.join(',')})"
          natures.push([n.id, label])
        end
        choice = pbMessage(_INTL("Quelle nature ?"), natures.map { |n| n[1] } + [_INTL("Annuler")], natures.length + 1)
        return if choice >= natures.length
        pkmn.nature = natures[choice][0]
      when :move0, :move1, :move2, :move3
        edit_move(field.to_s[-1].to_i)
        return
      when :evs, :ivs
        edit_stats(field == :evs)
        return
      when :gender
        return pbMessage(_INTL("Le sexe de cette espèce ne peut pas changer.")) if pkmn.singleGendered?
        choice = pbMessage(_INTL("Quel sexe ?"), [_INTL("Mâle"), _INTL("Femelle"), _INTL("Annuler")], 3)
        return if choice > 1
        (choice == 0) ? pkmn.makeMale : pkmn.makeFemale
      when :shiny
        pkmn.shiny = !pkmn.shiny?
      when :nickname
        text = pbEnterText(_INTL("Surnom ? (vide = aucun)"), 0, Pokemon::MAX_NAME_SIZE, (pkmn.nicknamed?) ? pkmn.name : "")
        pkmn.name = (text.to_s.strip.empty?) ? nil : text.strip
      when :advanced
        screen = PokemonDebugPartyScreen.new
        screen.pbPokemonDebug(pkmn, -1, nil, true)
        screen.pbEndScreen
      else
        return
      end
      @changed = true
    end

    def edit_move(slot)
      pkmn = @pkmn
      move = pkmn.moves[slot]
      cmds = [_INTL("Rechercher / liste complète"), _INTL("Attaques de l'espèce")]
      cmds.push(_INTL("Supprimer l'attaque")) if move
      cmds.push(_INTL("Annuler"))
      choice = pbMessage(_INTL("Attaque {1} ?", slot + 1), cmds, cmds.length)
      id = nil
      case choice
      when 0 then id = PokemonEditor.choose_data(GameData::Move, _INTL("Quelle attaque ?"), move&.id)
      when 1 then id = pbChooseMoveListForSpecies(pkmn.species, move&.id)
      when 2
        return if !move
        pkmn.moves.delete_at(slot)
        @changed = true
        return
      else
        return
      end
      return if !id
      if pkmn.moves.any? { |m| m.id == id }
        pbMessage(_INTL("{1} connaît déjà cette attaque.", pkmn.name))
        return
      end
      new_move = Pokemon::Move.new(id)
      if move
        pkmn.moves[slot] = new_move
      else
        pkmn.moves.push(new_move)
      end
      @changed = true
    end

    def edit_stats(evs)
      pkmn = @pkmn
      hash = (evs) ? pkmn.ev : pkmn.iv
      limit = (evs) ? Pokemon::EV_STAT_LIMIT : Pokemon::IV_STAT_LIMIT
      stats = TeamWriter::STAT_LABELS.keys
      loop do
        cmds = stats.map { |s| "#{GameData::Stat.get(s).name} : #{hash[s]}" }
        cmds.push((evs) ? _INTL("Tout à 0") : _INTL("Tout à 31"))
        cmds.push(_INTL("Terminé"))
        title = (evs) ? _INTL("EV (total {1}/{2})", hash.values.sum, Pokemon::EV_LIMIT) : _INTL("IV")
        choice = pbMessage(title, cmds, cmds.length)
        break if choice >= stats.length + 1
        if choice == stats.length
          stats.each { |s| hash[s] = (evs) ? 0 : Pokemon::IV_STAT_LIMIT }
          @changed = true
          next
        end
        stat = stats[choice]
        max = limit
        max = [limit, Pokemon::EV_LIMIT - (hash.values.sum - hash[stat])].min if evs
        params = ChooseNumberParams.new
        params.setRange(0, max)
        params.setDefaultValue([hash[stat], max].min)
        params.setCancelValue(-1)
        value = pbMessageChooseNumber(_INTL("{1} ? (0-{2})", GameData::Stat.get(stat).name, max), params)
        next if value < 0
        hash[stat] = value
        @changed = true
      end
      pkmn.calc_stats
    end
  end
end

class Pokemon
  # Copie indépendante (attaques, EV/IV compris) pour "Dupliquer".
  def clone_for_editor
    ret = Marshal.load(Marshal.dump(self))
    ret.instance_variable_set(:@personalID, rand(2**16) | (rand(2**16) << 16))
    return ret
  end
end

#===============================================================================
# Battle Simulator - chargement des équipes.
#
# Les équipes sont écrites dans BattleSimulator::TEAMS_FILE au format d'export
# de Pokémon Showdown : on peut les copier-coller depuis le teambuilder.
#
#   === [gen9] Nom de l'équipe ===
#
#   Surnom (Garchomp) (M) @ Choice Scarf
#   Ability: Rough Skin
#   Level: 100
#   Shiny: Yes
#   EVs: 252 Atk / 4 SpD / 252 Spe
#   Jolly Nature
#   IVs: 0 SpA
#   - Earthquake
#   - Dragon Claw
#
# Les noms anglais de Showdown, les noms du jeu et les IDs internes
# (GARCHOMP, CHOICESCARF...) sont acceptés. Formes : "Ninetales-Alola",
# "Rotom-Wash", "Urshifu-Rapid-Strike"... ou la ligne "Form: 1".
# Valeurs par défaut (comme Showdown) : IV 31, EV 0, bonheur 255, nature
# neutre, pas chromatique, 1er talent de l'espèce.
#===============================================================================
module BattleSimulator
  class TeamError < StandardError; end

  # Un Pokémon tel qu'écrit dans le fichier (noms pas encore résolus).
  class PokemonSet
    attr_accessor :species, :nickname, :gender, :item, :ability, :level, :shiny
    attr_accessor :nature, :evs, :ivs, :happiness, :moves, :ball, :form, :line_no

    def initialize(line_no)
      @line_no = line_no
      @evs     = {}
      @ivs     = {}
      @moves   = []
    end

    def label
      return (@nickname) ? "#{@nickname} (#{@species})" : @species.to_s
    end
  end

  class Team
    attr_reader   :name, :sets
    attr_accessor :format_tag

    def initialize(name, format_tag = nil)
      @name       = name
      @format_tag = format_tag
      @sets       = []
    end
  end

  module TeamLoader
    STAT_KEYS = {
      "hp" => :HP, "atk" => :ATTACK, "def" => :DEFENSE,
      "spa" => :SPECIAL_ATTACK, "spd" => :SPECIAL_DEFENSE, "spe" => :SPEED
    }
    FORM_ALIASES = {
      "alola" => "alolan", "galar" => "galarian", "hisui" => "hisuian",
      "paldea" => "paldean", "f" => "female", "m" => "male"
    }

    module_function

    #===========================================================================
    # Lecture du fichier
    #===========================================================================
    # Renvoie [équipes, erreurs]. Les erreurs de syntaxe n'empêchent pas de lire
    # les autres équipes.
    def load_file(path = BattleSimulator::TEAMS_FILE)
      return [[], [_INTL("Fichier d'équipes introuvable : {1}", path)]] if !File.exist?(path)
      text = File.open(path, "rb") { |f| f.read }
      return parse(text)
    end

    def parse(text)
      text = text.dup.force_encoding(Encoding::UTF_8)
      bom = [0xFEFF].pack("U")
      text = text[1..-1] if text.start_with?(bom)
      teams   = []
      errors  = []
      team    = nil
      current = nil
      text.split(/\r?\n/).each_with_index do |raw, i|
        line_no = i + 1
        line = raw.strip
        if line.empty?
          current = nil
          next
        end
        next if line.start_with?("#", "//")
        if line =~ /^===\s*(?:\[([^\]]*)\]\s*)?(.*?)\s*===$/
          team = Team.new(($2.empty?) ? _INTL("Équipe {1}", teams.length + 1) : $2, $1)
          teams.push(team)
          current = nil
          next
        end
        if !current
          if !team
            team = Team.new(_INTL("Équipe {1}", teams.length + 1))
            teams.push(team)
          end
          current = PokemonSet.new(line_no)
          begin
            parse_header(current, line)
          rescue TeamError => e
            errors.push(_INTL("Ligne {1} : {2}", line_no, e.message))
          end
          team.sets.push(current)
          next
        end
        begin
          parse_line(current, line)
        rescue TeamError => e
          errors.push(_INTL("Ligne {1} : {2}", line_no, e.message))
        end
      end
      teams.reject! { |t| t.sets.empty? }
      return teams, errors
    end

    # "Surnom (Espèce) (M) @ Objet"
    def parse_header(set, line)
      if line =~ /^(.*?)\s+@\s+(.*)$/
        line     = $1
        set.item = $2.strip
      end
      if line =~ /^(.*?)\s*\(([MF])\)$/
        line       = $1
        set.gender = ($2 == "M") ? 0 : 1
      end
      if line =~ /^(.*?)\s*\(([^()]+)\)$/
        set.nickname = $1.strip
        set.species  = $2.strip
      else
        set.species = line.strip
      end
      raise TeamError, _INTL("espèce manquante") if set.species.empty?
      set.nickname = nil if set.nickname && set.nickname.empty?
    end

    def parse_line(set, line)
      if line =~ /^[-~]\s*(.+)$/
        set.moves.push($1.split("/")[0].strip)
      elsif line =~ /^(\w+)\s+Nature$/i
        set.nature = $1
      elsif line =~ /^([\w ]+?)\s*:\s*(.*)$/
        key   = $1.downcase.delete(" ")
        value = $2.strip
        case key
        when "ability"              then set.ability   = value
        when "level"                then set.level     = parse_int(value, key)
        when "shiny"                then set.shiny     = (value.downcase == "yes")
        when "happiness", "friendship"
          set.happiness = parse_int(value, key)
        when "evs"                  then parse_stats(set.evs, value)
        when "ivs"                  then parse_stats(set.ivs, value)
        when "nature"               then set.nature    = value
        when "item"                 then set.item      = value
        when "gender"               then set.gender    = (value.upcase.start_with?("F")) ? 1 : 0
        when "form"                 then set.form      = parse_int(value, key)
        when "ball", "pokeball"     then set.ball      = value
        end
        # Autres clés Showdown (Tera Type, Gigantamax, Dynamax Level, Hidden
        # Power...) : sans effet dans Essentials, ignorées.
      else
        raise TeamError, _INTL("ligne non reconnue \"{1}\"", line)
      end
    end

    def parse_int(value, key)
      raise TeamError, _INTL("nombre attendu pour {1}", key) if value !~ /^\d+$/
      return value.to_i
    end

    # "252 HP / 4 Atk / 252 Spe"
    def parse_stats(hash, value)
      value.split("/").each do |part|
        part = part.strip
        if part !~ /^(\d+)\s+(\w+)$/
          raise TeamError, _INTL("statistique invalide \"{1}\"", part)
        end
        stat = STAT_KEYS[$2.downcase]
        raise TeamError, _INTL("statistique inconnue \"{1}\"", $2) if !stat
        hash[stat] = $1.to_i
      end
    end

    #===========================================================================
    # Résolution des noms (noms anglais, noms traduits ou IDs internes)
    #===========================================================================
    def normalize(str)
      ret = str.to_s.downcase
      ret = ret.tr("àâäáãéèêëíìîïóòôöõúùûüçñ", "aaaaaeeeeiiiiooooouuuucn")
      ret = ret.gsub("♀", "f").gsub("♂", "m")
      return ret.gsub(/[^a-z0-9]/, "")
    end

    def index_for(data_class)
      @indexes ||= {}
      return @indexes[data_class] if @indexes[data_class]
      index = {}
      data_class.each do |data|
        next if data.respond_to?(:form) && data.form != 0
        index[normalize(data.id)] ||= data.id
        index[normalize(data.real_name)] ||= data.id
        index[normalize(data.name)] ||= data.id
      end
      @indexes[data_class] = index
      return index
    end

    # À appeler si la langue du jeu change (les noms traduits changent).
    def clear_indexes
      @indexes = nil
    end

    # message : texte d'erreur avec {1} = nom introuvable.
    def find_id(data_class, name, message)
      id = index_for(data_class)[normalize(name)]
      raise TeamError, _INTL(message, name) if !id
      return id
    end

    def find_move(name)
      key = normalize(name)
      key = "hiddenpower" if key.start_with?("hiddenpower")
      id = index_for(GameData::Move)[key]
      raise TeamError, _INTL("attaque inconnue : \"{1}\"", name) if !id
      return id
    end

    # Renvoie [ID de l'espèce, numéro de forme].
    def find_species(name)
      index = index_for(GameData::Species)
      id = index[normalize(name)]
      return [id, 0] if id
      parts = name.split("-")
      (parts.length - 1).downto(1) do |n|
        id = index[normalize(parts[0...n].join("-"))]
        next if !id
        tokens = parts[n..-1].map { |part| normalize(part) }.reject { |t| t.empty? }
        form = find_form(id, tokens)
        if !form
          raise TeamError, _INTL("forme \"{1}\" inconnue pour {2}", parts[n..-1].join("-"), id)
        end
        return [id, form]
      end
      raise TeamError, _INTL("espèce inconnue : \"{1}\"", name)
    end

    def find_form(species, tokens)
      forms = []
      GameData::Species.each do |sp|
        next if sp.species != species || sp.form == 0
        form_name = normalize(sp.real_form_name)
        next if form_name.empty?
        next if !tokens.all? { |t| form_name.include?(t) || (FORM_ALIASES[t] && form_name.include?(FORM_ALIASES[t])) }
        if sp.mega_stone || sp.mega_move
          raise TeamError, _INTL("les Méga-Évolutions se font en combat : donnez la Méga-Gemme à {1}", species)
        end
        forms.push(sp.form)
      end
      return forms.min
    end

    #===========================================================================
    # Création des objets Pokemon
    #===========================================================================
    # Renvoie un tableau de Pokemon, ou lève TeamError avec toutes les erreurs.
    def build_party(team, owner)
      errors = []
      party  = []
      team.sets.each_with_index do |set, i|
        if i >= Settings::MAX_PARTY_SIZE
          errors.push(_INTL("{1} : plus de {2} Pokémon, les suivants sont ignorés.",
                            team.name, Settings::MAX_PARTY_SIZE))
          break
        end
        begin
          party.push(build_pokemon(set, owner))
        rescue TeamError => e
          errors.push(_INTL("{1}, ligne {2} ({3}) : {4}", team.name, set.line_no, set.label, e.message))
        end
      end
      raise TeamError, errors.join("\n") if !errors.empty?
      return party
    end

    def build_pokemon(set, owner)
      species, form = find_species(set.species)
      form = set.form if set.form
      species_form = GameData::Species.get_species_form(species, form)
      if !species_form || species_form.form != form
        raise TeamError, _INTL("{1} n'a pas de forme {2}", species, form)
      end
      level = set.level || BattleSimulator::DEFAULT_LEVEL
      max_level = GameData::GrowthRate.max_level
      raise TeamError, _INTL("niveau {1} invalide (1-{2})", level, max_level) if level < 1 || level > max_level
      item    = (set.item && !set.item.empty?) ? find_id(GameData::Item, set.item, "objet inconnu : \"{1}\"") : nil
      ability = (set.ability) ? find_id(GameData::Ability, set.ability, "talent inconnu : \"{1}\"") : nil
      nature  = (set.nature) ? find_id(GameData::Nature, set.nature, "nature inconnue : \"{1}\"") : nil
      ball    = (set.ball) ? find_id(GameData::Item, set.ball, "Poké Ball inconnue : \"{1}\"") : nil
      moves   = set.moves.map { |m| find_move(m) }.uniq
      raise TeamError, _INTL("plus de {1} attaques", Pokemon::MAX_MOVES) if moves.length > Pokemon::MAX_MOVES
      check_stats(set)
      # Création
      pkmn = Pokemon.new(species, level, owner, moves.empty?)
      # form_simple= : pose la forme sans les effets de "onSetForm" (Motisma qui
      # apprend une attaque avec un message, etc.). Les attaques sont posées après.
      if form > 0
        pkmn.form_simple = form
        pkmn.reset_moves if moves.empty?
      end
      pkmn.name = set.nickname if set.nickname
      case set.gender
      when 0 then pkmn.makeMale
      when 1 then pkmn.makeFemale
      end
      pkmn.shiny = (set.shiny) ? true : false
      if ability
        pkmn.ability = ability
      else
        pkmn.ability_index = 0
      end
      pkmn.nature    = nature || :HARDY
      pkmn.item      = item
      pkmn.happiness = set.happiness || 255
      pkmn.poke_ball = ball if ball
      GameData::Stat.each_main do |s|
        pkmn.iv[s.id] = set.ivs[s.id] || Pokemon::IV_STAT_LIMIT
        pkmn.ev[s.id] = set.evs[s.id] || 0
      end
      if !moves.empty?
        pkmn.forget_all_moves
        moves.each { |m| pkmn.learn_move(m) }
      end
      pkmn.record_first_moves
      pkmn.calc_stats
      pkmn.heal
      return pkmn
    end

    def check_stats(set)
      set.ivs.each do |stat, value|
        if value > Pokemon::IV_STAT_LIMIT
          raise TeamError, _INTL("IV {1} > {2}", value, Pokemon::IV_STAT_LIMIT)
        end
      end
      set.evs.each do |stat, value|
        if value > Pokemon::EV_STAT_LIMIT
          raise TeamError, _INTL("EV {1} > {2}", value, Pokemon::EV_STAT_LIMIT)
        end
      end
      total = set.evs.values.sum
      raise TeamError, _INTL("total d'EV {1} > {2}", total, Pokemon::EV_LIMIT) if total > Pokemon::EV_LIMIT
    end
  end
end

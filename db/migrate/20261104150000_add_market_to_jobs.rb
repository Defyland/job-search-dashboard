class AddMarketToJobs < ActiveRecord::Migration[8.1]
  BACKFILL_BATCH_SIZE = 500

  MARKET_VALUES = { "unknown" => 0, "national" => 1, "international" => 2 }.freeze

  # Frozen copies of the JobMarketClassifier dictionaries and precedence.
  # This migration must not depend on app code, so the rules are duplicated on purpose.
  PLACEHOLDER_PHRASES = [ "sem data publica" ].freeze

  BRAZIL_PHRASES = [
    "brasil",
    "brazil",
    "sao paulo",
    "rio de janeiro",
    "belo horizonte",
    "curitiba",
    "porto alegre",
    "florianopolis",
    "recife",
    "brasilia",
    "campinas"
  ].freeze

  RESTRICTED_BRAZIL_PHRASES = [
    "anywhere in brazil",
    "todo o brasil",
    "qualquer lugar do brasil"
  ].freeze

  GLOBAL_PHRASES = [
    "worldwide",
    "global",
    "anywhere",
    "work from anywhere",
    "qualquer lugar",
    "international"
  ].freeze

  REGION_PHRASES = [
    "latam",
    "latin america",
    "america latina",
    "south america",
    "americas",
    "north america",
    "emea",
    "europe",
    "apac"
  ].freeze

  FOREIGN_PHRASES = [
    "portugal",
    "united states",
    "usa",
    "canada",
    "mexico",
    "argentina",
    "chile",
    "colombia",
    "uruguay",
    "peru",
    "spain",
    "germany",
    "united kingdom",
    "ireland",
    "netherlands",
    "france",
    "india"
  ].freeze

  def up
    add_column :jobs, :market, :integer, null: false, default: 0
    add_index :jobs, :market

    job = Class.new(ActiveRecord::Base) { self.table_name = "jobs" }
    job.reset_column_information

    job.in_batches(of: BACKFILL_BATCH_SIZE) do |batch|
      rows = batch.pluck(:id, :location_text, :remote_text)

      rows.group_by { |_id, location_text, remote_text| market_for(location_text, remote_text) }.each do |market, grouped|
        job.where(id: grouped.map(&:first)).update_all(market: MARKET_VALUES.fetch(market))
      end
    end
  end

  def down
    remove_column :jobs, :market
  end

  private
    def market_for(location_text, remote_text)
      text = normalize("#{location_text} #{remote_text}")
      return "unknown" if text.empty?
      return "national" if phrase_in?(text, RESTRICTED_BRAZIL_PHRASES)
      return "international" if phrase_in?(text, GLOBAL_PHRASES) || phrase_in?(text, REGION_PHRASES)

      brazil = phrase_in?(text, BRAZIL_PHRASES)
      foreign = phrase_in?(text, FOREIGN_PHRASES)

      return "international" if brazil && foreign
      return "national" if brazil
      return "international" if foreign

      "unknown"
    end

    def normalize(value)
      text = I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squish
      PLACEHOLDER_PHRASES.reduce(text) { |current, phrase| current.gsub(/\b#{phrase}\b/, " ") }.squish
    end

    def phrase_in?(text, phrases)
      padded = " #{text} "
      phrases.any? { |phrase| padded.include?(" #{phrase} ") }
    end
end

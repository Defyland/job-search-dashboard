require "test_helper"

class JobMarketClassifierTest < ActiveSupport::TestCase
  # Literal input -> expected table. Only location_text and remote_text are inputs.
  CASES = [
    # Empty and placeholder inputs
    [ "blank both", nil, nil, "unknown" ],
    [ "blank strings", "", "   ", "unknown" ],
    [ "sem data publica", "Sem data pública", nil, "unknown" ],
    [ "sem data publica with remote", "Sem data pública", "Remote", "unknown" ],

    # Generic remote without a market signal
    [ "generic Remote", nil, "Remote", "unknown" ],
    [ "generic Remoto", nil, "Remoto", "unknown" ],
    [ "Trabalho remoto", "", "Trabalho remoto", "unknown" ],

    # Restricted Brazil phrases (national, override global words)
    [ "anywhere in Brazil", "Anywhere in Brazil", nil, "national" ],
    [ "todo o brasil", "Todo o Brasil", nil, "national" ],
    [ "qualquer lugar do brasil", "Qualquer lugar do Brasil", nil, "national" ],
    [ "restricted overrides worldwide", "Worldwide, anywhere in Brazil", nil, "national" ],
    [ "restricted overrides global", "Global", "Anywhere in Brazil", "national" ],

    # Brazil dictionary (national)
    [ "Brazil location", "Brazil", nil, "national" ],
    [ "Brasil location", "Brasil", nil, "national" ],
    [ "Remote with Brazil", "Brazil", "Remote", "national" ],
    [ "Brasil with remote Remote", "Brasil", "Remote", "national" ],
    [ "Sao Paulo", "Sao Paulo", nil, "national" ],
    [ "São Paulo accented", "São Paulo", nil, "national" ],
    [ "Rio de Janeiro", "Rio de Janeiro", nil, "national" ],
    [ "Belo Horizonte", "Belo Horizonte", nil, "national" ],
    [ "Curitiba", "Curitiba", nil, "national" ],
    [ "Porto Alegre", "Porto Alegre", nil, "national" ],
    [ "Florianopolis", "Florianópolis", nil, "national" ],
    [ "Recife", "Recife", nil, "national" ],
    [ "Brasilia", "Brasília", nil, "national" ],
    [ "Campinas", "Campinas", nil, "national" ],
    [ "remote Brazil only in remote_text", nil, "Brazil remote", "national" ],

    # Global phrases (international)
    [ "Worldwide", "Worldwide", nil, "international" ],
    [ "Global", "Global", nil, "international" ],
    [ "Anywhere", "Anywhere", nil, "international" ],
    [ "Work from anywhere", "Work from anywhere", nil, "international" ],
    [ "Qualquer lugar", "Qualquer lugar", nil, "international" ],
    [ "International", "International", nil, "international" ],
    [ "Worldwide including Brazil", "Worldwide including Brazil", nil, "international" ],
    [ "Global incl Brazil", "Global, incl. Brazil", nil, "international" ],

    # Region phrases (international, with or without Brazil)
    [ "LatAm alone", "LatAm", nil, "international" ],
    [ "LatAm with Brazil", "LatAm, Brazil", nil, "international" ],
    [ "Latin America", "Latin America", nil, "international" ],
    [ "America Latina with Brasil", "America Latina", "Brasil", "international" ],
    [ "South America", "South America", nil, "international" ],
    [ "Americas", "Americas", nil, "international" ],
    [ "North America", "North America", nil, "international" ],
    [ "EMEA", "EMEA", nil, "international" ],
    [ "Europe", "Europe", nil, "international" ],
    [ "APAC", "APAC", nil, "international" ],

    # Brazil combined with a foreign country (international)
    [ "Brazil, Portugal", "Brazil, Portugal", nil, "international" ],
    [ "Brasil e Portugal", "Brasil e Portugal", nil, "international" ],

    # Foreign-only (international)
    [ "Portugal", "Portugal", nil, "international" ],
    [ "United States", "United States", nil, "international" ],
    [ "USA", "USA", nil, "international" ],
    [ "Canada", "Canada", nil, "international" ],
    [ "Mexico", "Mexico", nil, "international" ],
    [ "Argentina", "Argentina", nil, "international" ],
    [ "Chile", "Chile", nil, "international" ],
    [ "Colombia", "Colombia", nil, "international" ],
    [ "Uruguay", "Uruguay", nil, "international" ],
    [ "Peru", "Peru", nil, "international" ],
    [ "Spain", "Spain", nil, "international" ],
    [ "Germany", "Germany", nil, "international" ],
    [ "United Kingdom", "United Kingdom", nil, "international" ],
    [ "Ireland", "Ireland", nil, "international" ],
    [ "Netherlands", "Netherlands", nil, "international" ],
    [ "France", "France", nil, "international" ],
    [ "India", "India", nil, "international" ],
    [ "Foreign in remote_text", nil, "Remote from Portugal", "international" ],

    # Abbreviations and unlisted countries stay unknown
    [ "us abbreviation", "US", nil, "unknown" ],
    [ "uk abbreviation", "UK", nil, "unknown" ],
    [ "br abbreviation", "BR", nil, "unknown" ],
    [ "sp abbreviation", "SP", nil, "unknown" ],
    [ "rj abbreviation", "RJ", nil, "unknown" ],
    [ "unlisted country Kenya", "Kenya", nil, "unknown" ],
    [ "Paulo alone is not Sao Paulo", "Paulo", nil, "unknown" ],
    [ "Porto alone is not Porto Alegre", "Porto", nil, "unknown" ],

    # Whole-word boundaries
    [ "brazilian is not Brazil", "Brazilian company", nil, "unknown" ],
    [ "globally is not global", "Globally distributed team", nil, "unknown" ],
    [ "Brasileiro is not Brasil", "Brasileiro", nil, "unknown" ],
    [ "Portugues is not Portugal", "Portuguese speakers", nil, "unknown" ],
    [ "Latinamerica is not latin america", "Latinamerica", nil, "unknown" ]
  ].freeze

  CASES.each do |name, location_text, remote_text, expected|
    test "classifies #{name}" do
      assert_equal expected, JobMarketClassifier.call(location_text:, remote_text:)
    end
  end

  test "returns a string" do
    assert_kind_of String, JobMarketClassifier.call(location_text: "Brazil", remote_text: nil)
  end

  test "ignores title company language description and raw payload" do
    # Only location_text and remote_text are inputs: the classifier has no other keyword.
    assert_raises(ArgumentError) do
      JobMarketClassifier.call(location_text: nil, remote_text: nil, title: "Brazil Engineer")
    end
  end
end

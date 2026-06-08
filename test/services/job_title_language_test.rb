require "test_helper"

class JobTitleLanguageTest < ActiveSupport::TestCase
  test "detects portuguese titles" do
    assert_equal "portuguese", JobTitleLanguage.detect("Desenvolvedor Frontend Sênior React")
  end

  test "detects english titles" do
    assert_equal "english", JobTitleLanguage.detect("Senior Frontend Engineer React")
  end

  test "returns unknown for neutral titles" do
    assert_equal "unknown", JobTitleLanguage.detect("Senior Fullstack React")
  end
end

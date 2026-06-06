require "test_helper"

class SearchRunItemTest < ActiveSupport::TestCase
  test "allows rejected items without a linked job" do
    item = SearchRunItem.new(search_run: search_runs(:recent), outcome: :rejected, reason: "descartada")
    assert item.valid?
  end
end

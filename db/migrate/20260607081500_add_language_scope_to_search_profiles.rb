class AddLanguageScopeToSearchProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :search_profiles, :language_scope, :integer, null: false, default: 0
    add_index :search_profiles, :language_scope
  end
end

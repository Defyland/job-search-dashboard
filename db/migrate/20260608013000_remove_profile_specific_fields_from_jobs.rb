class RemoveProfileSpecificFieldsFromJobs < ActiveRecord::Migration[8.1]
  def up
    remove_index :jobs, column: %i[lifecycle_state user_state match_strength], if_exists: true
    remove_column :jobs, :seniority
    remove_column :jobs, :match_strength
    remove_column :jobs, :user_state
    remove_column :jobs, :reason
    remove_column :jobs, :score
    remove_column :jobs, :stack_tags
  end

  def down
    add_column :jobs, :seniority, :string, null: false, default: "senior"
    add_column :jobs, :match_strength, :integer, null: false, default: 0
    add_column :jobs, :user_state, :integer, null: false, default: 0
    add_column :jobs, :reason, :text, null: false, default: ""
    add_column :jobs, :score, :integer, null: false, default: 0
    add_column :jobs, :stack_tags, :text, null: false, array: true, default: []
    add_index :jobs, %i[lifecycle_state user_state match_strength]
  end
end

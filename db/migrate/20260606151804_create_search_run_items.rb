class CreateSearchRunItems < ActiveRecord::Migration[8.1]
  def change
    create_table :search_run_items do |t|
      t.references :search_run, null: false, foreign_key: true
      t.references :job, foreign_key: true
      t.integer :outcome, null: false, default: 0
      t.text :reason, null: false, default: ""
      t.jsonb :payload, null: false, default: {}
      t.string :title
      t.string :company_name
      t.string :apply_url
      t.string :canonical_url

      t.timestamps
    end

    add_index :search_run_items, :outcome
  end
end

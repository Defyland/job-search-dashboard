class CreateWaitlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :waitlist_entries do |t|
      t.string :email_address, null: false
      t.string :ip_address
      t.text :user_agent
      t.datetime :notified_at
      t.text :notification_error

      t.timestamps
    end

    add_index :waitlist_entries, :email_address, unique: true
    add_index :waitlist_entries, :created_at
  end
end

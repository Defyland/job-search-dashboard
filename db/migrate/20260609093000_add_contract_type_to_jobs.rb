class AddContractTypeToJobs < ActiveRecord::Migration[8.1]
  def up
    add_column :jobs, :contract_type, :integer, null: false, default: 0
    add_index :jobs, :contract_type

    say_with_time "Backfilling job contract types" do
      Job.reset_column_information
      Job.find_each { |job| job.save!(touch: false) }
    end
  end

  def down
    remove_index :jobs, :contract_type
    remove_column :jobs, :contract_type
  end
end

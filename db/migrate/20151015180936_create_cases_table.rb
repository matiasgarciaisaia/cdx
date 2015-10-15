class CreateCasesTable < ActiveRecord::Migration
  def change
    create_table :cases do |t|
      t.string  :uuid,        limit: 255
      t.integer :source_id
      t.string  :source_type, limit: 60
    end

    add_index :cases, :uuid, unique: true
  end
end

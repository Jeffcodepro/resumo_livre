class AddAccessFlagsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :admin,       :boolean, default: false, null: false
    add_column :users, :approved,    :boolean, default: false, null: false
    add_column :users, :approved_at, :datetime
    add_column :users, :blocked,     :boolean, default: false, null: false
    add_column :users, :paid,        :boolean, default: false, null: false

    add_index :users, :admin
    add_index :users, :approved
    add_index :users, :blocked
    add_index :users, :paid
  end
end

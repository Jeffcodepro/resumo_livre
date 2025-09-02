class AddUniqueLowercaseEmailIndex < ActiveRecord::Migration[7.1]
  def change
    # Remova um índice antigo, se existir
    remove_index :users, :email if index_exists?(:users, :email)

    # Índice único em LOWER(email)
    add_index :users, "LOWER(email)", unique: true, name: "index_users_on_lower_email"
  end
end

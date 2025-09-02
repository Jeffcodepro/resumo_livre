class AddUniqueIndexOnCnpj < ActiveRecord::Migration[7.1]
  def change
    add_index :users, :cnpj, unique: true
  end
end

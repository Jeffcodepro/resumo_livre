class AddProfileFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :full_name, :string
    add_column :users, :trade_name, :string
    add_column :users, :cnpj, :string
    add_column :users, :whatsapp, :string
  end
end

class AddLineCountToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :line_count, :integer, null: false, default: 1
  end
end

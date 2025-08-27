class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true

      t.string   :order_number, null: false
      t.string   :platform,     null: false, default: "SHEIN"
      t.string   :status
      t.datetime :order_date
      t.decimal  :value_total, precision: 12, scale: 2, default: 0
      t.jsonb    :raw, default: {}

      t.timestamps
    end

    add_index :orders, [:user_id, :order_number], unique: true
    add_index :orders, [:user_id, :platform]
    add_check_constraint :orders, "platform = 'SHEIN'", name: "orders_platform_shein_only"
  end
end

class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.references :user, null: false, foreign_key: true

      t.string   :order_number, null: false
      t.string   :platform,     null: false, default: "SHEIN"
      t.decimal  :amount, precision: 12, scale: 2, default: 0
      t.datetime :paid_at
      t.jsonb    :raw, default: {}

      t.timestamps
    end

    add_index :payments, [:user_id, :order_number], unique: true
    add_index :payments, [:user_id, :platform]
    add_check_constraint :payments, "platform = 'SHEIN'", name: "payments_platform_shein_only"
  end
end

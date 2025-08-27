# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_08_26_004629) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "orders", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "order_number", null: false
    t.string "platform", default: "SHEIN", null: false
    t.string "status"
    t.datetime "order_date"
    t.decimal "value_total", precision: 12, scale: 2, default: "0.0"
    t.jsonb "raw", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "line_count", default: 1, null: false
    t.string "order_type"
    t.string "exchange_order_number"
    t.string "shipping_mode"
    t.boolean "instado", default: false
    t.boolean "is_lost", default: false
    t.boolean "should_stay", default: false
    t.boolean "has_issues", default: false
    t.text "product_name"
    t.string "product_number"
    t.string "variation"
    t.string "seller_sku"
    t.string "shein_sku"
    t.string "skc"
    t.string "item_id"
    t.string "product_status"
    t.string "inventory_id"
    t.string "exchange_code"
    t.text "exchange_reason"
    t.string "exchange_product_id"
    t.boolean "is_blocked", default: false
    t.datetime "label_print_deadline"
    t.datetime "collection_required_at"
    t.datetime "collected_at"
    t.string "tracking_code"
    t.string "last_mile_provider"
    t.boolean "merchant_package", default: false
    t.boolean "passes_through_warehouse", default: false
    t.string "first_mile_provider"
    t.string "first_mile_waybill"
    t.string "seller_currency"
    t.decimal "product_price", precision: 12, scale: 2
    t.decimal "coupon_value", precision: 12, scale: 2
    t.decimal "store_campaign_discount", precision: 12, scale: 2
    t.decimal "commission", precision: 12, scale: 2
    t.index ["order_type"], name: "index_orders_on_order_type"
    t.index ["user_id", "order_number", "item_id"], name: "idx_orders_user_order_item_unique", unique: true, where: "(item_id IS NOT NULL)"
    t.index ["user_id", "platform"], name: "index_orders_on_user_id_and_platform"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.check_constraint "platform::text = 'SHEIN'::text", name: "orders_platform_shein_only"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "order_number", null: false
    t.string "platform", default: "SHEIN", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0"
    t.datetime "paid_at"
    t.jsonb "raw", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "site"
    t.string "related_order_number"
    t.string "invoice_number"
    t.date "seller_delivery_date"
    t.datetime "delivered_at"
    t.string "invoice_type"
    t.decimal "product_price_summary", precision: 12, scale: 2
    t.decimal "campaign_discount", precision: 12, scale: 2
    t.decimal "store_coupon_value", precision: 12, scale: 2
    t.decimal "payment_commission", precision: 12, scale: 2
    t.decimal "freight_intermediation_fee", precision: 12, scale: 2
    t.decimal "storage_operation_fee", precision: 12, scale: 2
    t.decimal "return_processing_fee", precision: 12, scale: 2
    t.index ["invoice_number"], name: "index_payments_on_invoice_number"
    t.index ["user_id", "order_number"], name: "index_payments_on_user_id_and_order_number", unique: true
    t.index ["user_id", "platform"], name: "index_payments_on_user_id_and_platform"
    t.index ["user_id"], name: "index_payments_on_user_id"
    t.check_constraint "platform::text = 'SHEIN'::text", name: "payments_platform_shein_only"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name"
    t.string "trade_name"
    t.string "cnpj"
    t.string "whatsapp"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "orders", "users"
  add_foreign_key "payments", "users"
end

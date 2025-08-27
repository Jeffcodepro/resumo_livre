class ChangeOrdersUniqueIndexToOrderNumberItem < ActiveRecord::Migration[7.1]
  def up
    # remove o índice antigo único em [:user_id, :order_number], se existir
    if index_exists?(:orders, [:user_id, :order_number])
      remove_index :orders, column: [:user_id, :order_number]
    end

    # se por acaso existir algum índice antigo com esse nome, remove
    if index_exists?(:orders, nil, name: "index_orders_on_user_id_and_item_id_unique")
      remove_index :orders, name: "index_orders_on_user_id_and_item_id_unique"
    end

    # cria o índice único parcial novo: (user_id, order_number, item_id) quando item_id NÃO é nulo
    unless index_exists?(:orders, nil, name: "idx_orders_user_order_item_unique")
      add_index :orders,
                [:user_id, :order_number, :item_id],
                unique: true,
                where: "item_id IS NOT NULL",
                name: "idx_orders_user_order_item_unique"
    end
  end

  def down
    # remove o índice novo, se existir
    if index_exists?(:orders, nil, name: "idx_orders_user_order_item_unique")
      remove_index :orders, name: "idx_orders_user_order_item_unique"
    end

    # recria o índice único antigo em [:user_id, :order_number], se quiser voltar
    unless index_exists?(:orders, [:user_id, :order_number])
      add_index :orders, [:user_id, :order_number], unique: true
    end

    # (opcional) recriar um índice antigo por nome, se você realmente o tinha:
    unless index_exists?(:orders, nil, name: "index_orders_on_user_id_and_item_id_unique")
      add_index :orders, [:user_id, :item_id], unique: true, name: "index_orders_on_user_id_and_item_id_unique"
    end
  end
end

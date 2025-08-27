class Order < ApplicationRecord
  belongs_to :user

  before_validation :force_platform

  validates :order_number, presence: true, uniqueness: { scope: :user_id }
  validates :platform, inclusion: { in: %w[SHEIN] }

  scope :not_refunded, -> { where("COALESCE(LOWER(status),'') NOT LIKE ?", "%reembolsado por cliente%") }

  scope :valid_for_kpis, -> {
    for_shein
      .where.not(status: nil)
      .where("LOWER(status) NOT LIKE ?", "%reembolsado por cliente%")
  }

  private

  def force_platform
    self.platform = "SHEIN"
  end
end

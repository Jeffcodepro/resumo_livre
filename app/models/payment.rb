class Payment < ApplicationRecord
  belongs_to :user

  before_validation :force_platform

  validates :order_number, presence: true, uniqueness: { scope: :user_id }
  validates :platform, inclusion: { in: %w[SHEIN] }

  private

  def force_platform
    self.platform = "SHEIN"
  end
end

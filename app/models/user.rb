class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Campos que NÃO podem mudar após criar a conta
  attr_readonly :full_name, :trade_name, :cnpj

  # Normalizações
  before_validation :normalize_email!, :normalize_whatsapp!
  before_validation :normalize_cnpj!, on: :create

  # Não permitir troca real de e-mail
  validate :email_unchanged, on: :update

  # Associações
  has_many :orders,   dependent: :destroy, inverse_of: :user
  has_many :payments, dependent: :destroy, inverse_of: :user

  # -------- Validações --------
  EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP # robusto e já incluso na stdlib

  validates :email,
    presence:   true,
    format:     { with: EMAIL_REGEX },
    uniqueness: { case_sensitive: false }

  validates :cnpj,
    presence:   true,
    uniqueness: true
  validate :cnpj_must_be_valid

  # -------- Métodos públicos --------
  def first_name
    n = full_name.to_s.strip
    return n.split(/\s+/).first if n.present?
    email.to_s.split("@").first
  end

  after_commit :notify_n8n_signup, on: :create


  private

  # ------------ Normalizações ------------
  def normalize_email!
    self.email = email.to_s.strip.downcase.presence
  end

  def normalize_cnpj!
    return if persisted?
    self.cnpj = only_digits(cnpj).presence
  end

  def normalize_whatsapp!
    self.whatsapp = only_digits(whatsapp) if self.respond_to?(:whatsapp)
  end

  def only_digits(str)
    str.to_s.gsub(/\D/, "")
  end

  # ------------ Restrições ------------
  def email_unchanged
    # Só barra se o valor realmente mudou (ignorando caixa e espaços)
    if will_save_change_to_email? &&
       email.to_s.strip.downcase != email_was.to_s.strip.downcase
      errors.add(:email, "não pode ser alterado")
      self.email = email_was
    end
  end

  # ------------ CNPJ: validação pura Ruby ------------
  # Regras:
  # - 14 dígitos
  # - não pode ser todos os dígitos iguais
  # - dígitos verificadores corretos (módulo 11)
  def cnpj_must_be_valid
    val = cnpj.to_s
    return if val.blank? # presence já cobre mensagem

    unless cnpj_valid?(val)
      errors.add(:cnpj, "inválido")
    end
  end

  def cnpj_valid?(value)
    digits = only_digits(value)
    return false unless digits.length == 14
    return false if digits.chars.uniq.length == 1 # rejeita "00000000000000" etc.

    base = digits[0, 12].chars.map!(&:to_i)
    d1   = calc_cnpj_digit(base, 1)
    d2   = calc_cnpj_digit(base + [d1], 2)

    digits[-2, 2] == "#{d1}#{d2}"
  end

  # peso para d1: 5,4,3,2,9,8,7,6,5,4,3,2
  # peso para d2: 6,5,4,3,2,9,8,7,6,5,4,3,2
  def calc_cnpj_digit(nums, which)
    weights = which == 1 ? [5,4,3,2,9,8,7,6,5,4,3,2] : [6,5,4,3,2,9,8,7,6,5,4,3,2]
    sum = nums.each_with_index.sum { |n, i| n * weights[i] }
    mod = sum % 11
    mod < 2 ? 0 : (11 - mod)
  end

  def notify_n8n_signup
    N8nUserSignupJob.perform_later(id)
  end
end

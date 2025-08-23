class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Campos que NÃO podem mudar após criar a conta
  attr_readonly :full_name, :trade_name, :cnpj

  # Normalizações
  before_validation :normalize_on_create, on: :create
  before_validation :normalize_updatable_fields, on: :update

  # Não permitir troca real de e-mail
  validate :email_unchanged, on: :update

  # ---- métodos públicos ----
  def first_name
    n = full_name.to_s.strip
    return n.split(/\s+/).first if n.present?
    email.to_s.split("@").first
  end

  private

  def digits(str)
    str.to_s.gsub(/\D/, "")
  end

  # Executa só no cadastro
  def normalize_on_create
    self.email    = email.to_s.downcase.strip if email.present?
    self.cnpj     = digits(cnpj)              if cnpj.present?
    self.whatsapp = digits(whatsapp)          if whatsapp.present?
  end

  # Executa nas edições: só campos editáveis
  def normalize_updatable_fields
    self.whatsapp = digits(whatsapp) if whatsapp.present?
  end

  def email_unchanged
    # Só barra se o valor realmente mudou (ignorando caixa)
    if will_save_change_to_email? && email.to_s.downcase != email_was.to_s.downcase
      errors.add(:email, "não pode ser alterado")
      self.email = email_was
    end
  end
end

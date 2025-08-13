# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# db/seeds.rb
puts "▶️  Criando usuário padrão..."

email    = ENV.fetch("SEED_USER_EMAIL", "admin@example.com")
password = ENV.fetch("SEED_USER_PASSWORD", "123456")

user = User.find_or_initialize_by(email: email)
user.password = password
user.password_confirmation = password

# Se o Devise tiver :confirmable habilitado
user.skip_confirmation! if user.respond_to?(:skip_confirmation!)

user.save!

puts "✅  Usuário criado/atualizado:"
puts "    Email:    #{email}"
puts "    Senha:    #{password}"

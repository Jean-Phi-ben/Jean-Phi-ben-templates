# Template Rails: Chalet de Prestige
# Usage: rails new app_name -m path/to/template.rb

run "if uname | grep -q 'Darwin'; then pgrep spring | xargs kill -9; fi"

# 1. Gemfile - Nettoyage et ajouts (Point 2, 3, 4)
########################################
# On retire les anciennes gems Bootstrap/Sprockets du script initial
gsub_file("Gemfile", /^gem "bootstrap".*\n/, "")
gsub_file("Gemfile", /^gem "sassc-rails".*\n/, "")
gsub_file("Gemfile", /^gem "propshaft".*\n/, "") # Rails 8 gère cela par défaut ou via Tailwind

inject_into_file "Gemfile", before: "group :development, :test do" do
  <<~RUBY
    gem "pundit"
    gem "omniauth-google-oauth2"
    gem "omniauth-facebook"
    gem "omniauth-apple"
    gem "dotenv-rails"
  RUBY
end

# 2. Tailwind & Assets (Point 2 & 7)
########################################
gem "tailwindcss-rails"

# 3. Layout & Fluidité JS (Point 7 & 8)
########################################
# Création du partial pour isoler le JS du Head
file "app/views/layouts/_head_scripts.html.erb", <<~HTML
  <%# Scripts chargés dans le head pour éviter les sauts de contenu %>
  <%= javascript_importmap_tags %>
HTML

# Modification de application.html.erb
# On insère le rendu du head et le div "main-content"
gsub_file(
  "app/views/layouts/application.html.erb",
  '<%= javascript_importmap_tags %>',
  '<%= render "layouts/head_scripts" %>'
)

gsub_file(
  "app/views/layouts/application.html.erb",
  '<%= yield %>',
  <<~HTML
    <div id="main-content" class="container mx-auto px-4 py-8">
      <%= yield %>
    </div>
  HTML
)

# 4. Processus après installation des Gems
########################################
after_bundle do
  # Installation Tailwind
  run "bundle exec rails tailwindcss:install"

  # Authentification native Rails 8 (Point 3)
  # Remplace 'devise' par le système léger de Rails 8
  generate "authentication"

  # Installation Pundit (Point 1)
  generate "pundit:install"

  # Namespace Admin (Point 1)
  generate :controller, "admin/dashboard", "index", "--no-test-framework"
  
  # Ajout du rôle admin aux utilisateurs (Point 5 & 6)
  generate :migration, "AddAdminToUsers", "admin:boolean"
  
  # Configuration des routes
  route "namespace :admin do root to: 'dashboard#index' end"
  route 'root to: "pages#home"'
  generate :controller, "pages", "home", "--skip-routes"

  # Seed pour les utilisateurs tests (Point 5 & 6)
  append_file "db/seeds.rb", <<~RUBY
    User.destroy_all
    User.create!(
      email_address: "admin@prestige.com",
      password: "password123",
      admin: true
    )
    User.create!(
      email_address: "client@prestige.com",
      password: "password123",
      admin: false
    )
    puts "Base de données initialisée : admin@prestige.com / client@prestige.com"
  RUBY

  # Database setup
  rails_command "db:prepare"
  rails_command "db:seed"

  # OmniAuth Initializer (Point 4)
  file "config/initializers/omniauth.rb", <<~RUBY
    Rails.application.config.middleware.use OmniAuth::Builder do
      provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']
      provider :facebook, ENV['FACEBOOK_APP_ID'], ENV['FACEBOOK_APP_SECRET']
      provider :apple, ENV['APPLE_CLIENT_ID'], ENV['APPLE_TEAM_ID'], ENV['APPLE_KEY_ID'], ENV['APPLE_PRIVATE_KEY']
    end
  RUBY

  # Dotenv
  run "touch .env"

  # Git final commit
  git :init
  git add: "."
  git commit: "-m 'Initial setup: Rails 8 Auth, Tailwind, Pundit, Admin namespace'"
end

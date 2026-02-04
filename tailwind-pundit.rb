# Template Rails: Chalet de Prestige (Corrected for Rails 8)
run "if uname | grep -q 'Darwin'; then pgrep spring | xargs kill -9; fi"

# 1. Gemfile - Nettoyage et ajouts
########################################
# On retire SEULEMENT ce qui est inutile (Bootstrap/Sprockets)
# ON GARDE PROPSHAFT pour Rails 8
gsub_file("Gemfile", /^gem "bootstrap".*\n/, "")
gsub_file("Gemfile", /^gem "sassc-rails".*\n/, "")

inject_into_file "Gemfile", before: "group :development, :test do" do
  <<~RUBY
    gem "pundit"
    gem "omniauth-google-oauth2"
    gem "omniauth-facebook"
    gem "omniauth-apple"
    gem "dotenv-rails"
  RUBY
end

# 2. Assets & Layout (Point 7 & 8)
########################################
gem "tailwindcss-rails"

file "app/views/layouts/_head_scripts.html.erb", <<~HTML
  <%# Scripts chargés dans le head %>
  <%= javascript_importmap_tags %>
HTML

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

# 3. Processus après installation
########################################
after_bundle do
  # Crucial : On s'assure que Propshaft est actif avant Tailwind
  run "bundle exec rails tailwindcss:install"

  # Authentification native Rails 8
  generate "authentication"

  # Installation Pundit
  generate "pundit:install"

  # Namespace Admin
  generate :controller, "admin/dashboard", "index", "--no-test-framework"
  generate :migration, "AddAdminToUsers", "admin:boolean"
  
  # Configuration des routes
  route "namespace :admin do root to: 'dashboard#index' end"
  route 'root to: "pages#home"'
  generate :controller, "pages", "home", "--skip-routes"

  # Seed
  append_file "db/seeds.rb", <<~RUBY
    User.destroy_all
    User.create!(email_address: "admin@prestige.com", password: "password123", admin: true)
    User.create!(email_address: "client@prestige.com", password: "password123", admin: false)
    puts "Base de données initialisée !"
  RUBY

  # Database setup
  rails_command "db:prepare"
  rails_command "db:seed"

  # OmniAuth Initializer
  file "config/initializers/omniauth.rb", <<~RUBY
    Rails.application.config.middleware.use OmniAuth::Builder do
      provider :google_oauth2, ENV['GOOGLE_CLIENT_ID'], ENV['GOOGLE_CLIENT_SECRET']
      provider :facebook, ENV['FACEBOOK_APP_ID'], ENV['FACEBOOK_APP_SECRET']
      provider :apple, ENV['APPLE_CLIENT_ID'], ENV['APPLE_TEAM_ID'], ENV['APPLE_KEY_ID'], ENV['APPLE_PRIVATE_KEY']
    end
  RUBY

  run "touch .env"

  # Git final
  git :init
  git add: "."
  git commit: "-m 'Initial setup: Rails 8 Auth, Tailwind, Pundit, Admin namespace'"
end

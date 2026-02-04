run "if uname | grep -q 'Darwin'; then pgrep spring | xargs kill -9; fi"

# 1. Configuration des Gems
########################################
gem "propshaft"
gem "tailwindcss-rails"

inject_into_file "Gemfile", before: "group :development, :test do" do
  <<~RUBY
    gem "pundit"
    gem "omniauth-google-oauth2"
    gem "omniauth-facebook"
    gem "omniauth-apple"
    gem "dotenv-rails"
  RUBY
end

# 2. Layout & Fluidité (Points 7 & 8)
########################################
file "app/views/layouts/_head_scripts.html.erb", "<%= javascript_importmap_tags %>"
gsub_file "app/views/layouts/application.html.erb", '<%= javascript_importmap_tags %>', '<%= render "layouts/head_scripts" %>'
gsub_file "app/views/layouts/application.html.erb", '<%= yield %>', <<~HTML
  <div id="main-content" class="container mx-auto px-4 py-8">
    <%= yield %>
  </div>
HTML

# 3. Installation et Génération
########################################
after_bundle do
  run "bundle exec rails tailwindcss:install"
  generate "authentication"
  generate "pundit:install"
  
  # Génération de l'admin
  generate :controller, "admin/dashboard", "index", "--no-test-framework"
  generate :migration, "AddAdminToUsers", "admin:boolean"
  
  # Correction de la migration pour le default
  migration_file = Dir.glob("db/migrate/*_add_admin_to_users.rb").first
  gsub_file migration_file, /t.boolean :admin/, "t.boolean :admin, default: false" if migration_file

  # --- AJOUT DES FICHIERS DE LOGIQUE ADMIN ---
  
  # Création de la Policy Admin (Point de vigilance)
  file "app/policies/admin_policy.rb", <<~RUBY
    class AdminPolicy < ApplicationPolicy
      def index?
        user&.admin?
      end
    end
  RUBY

  # Modification du Dashboard Controller pour utiliser Pundit
  file "app/controllers/admin/dashboard_controller.rb", <<~RUBY, force: true
    class Admin::DashboardController < ApplicationController
      def index
        authorize :admin, :index?
      end
    end
  RUBY

  # Injection de Pundit dans ApplicationController
  inject_into_file "app/controllers/application_controller.rb", after: "include Authentication" do
    "\n  include Pundit::Authorization"
  end

  # Routes
  route "namespace :admin do root to: 'dashboard#index' end"
  route "root to: 'pages#home'"
  generate :controller, "pages", "home", "--skip-routes"

  # Seed
  file "db/seeds.rb", <<~RUBY, force: true
    User.destroy_all
    User.create!(email_address: "admin@chalet.com", password: "password123", admin: true)
    User.create!(email_address: "client@chalet.com", password: "password123", admin: false)
    puts "Base de données initialisée !"
  RUBY

  # DB Setup
  rails_command "db:prepare"
  rails_command "db:seed"

  run "touch .env"
  git :init
  git add: "."
  git commit: "-m 'Setup complet : Auth + Pundit Admin Policy + Tailwind'"
end

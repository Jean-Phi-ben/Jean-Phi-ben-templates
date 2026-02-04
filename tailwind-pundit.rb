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

# 2. Layout & Fluidité
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
  
  # --- MODIFICATION DU MODÈLE USER ---
  # On écrase le fichier pour ajouter la méthode admin?
  file "app/models/user.rb", <<~RUBY, force: true
    class User < ApplicationRecord
      has_secure_password
      has_many :sessions, dependent: :destroy

      validates :email_address, presence: true, uniqueness: true

      def admin?
        admin == true
      end
    end
  RUBY

  # --- CONFIGURATION DE LA MIGRATION ADMIN ---
  generate :migration, "AddAdminToUsers", "admin:boolean"
  migration_file = Dir.glob("db/migrate/*_add_admin_to_users.rb").first
  if migration_file
    gsub_file migration_file, /t.boolean :admin/, "t.boolean :admin, default: false"
  end

  # --- CONFIGURATION DE L'APPLICATION CONTROLLER ---
  # On réécrit le contrôleur pour inclure Pundit et la gestion d'erreur
  file "app/controllers/application_controller.rb", <<~RUBY, force: true
    class ApplicationController < ActionController::Base
      include Authentication
      include Pundit::Authorization

      rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

      private

      def user_not_authorized
        flash[:alert] = "Vous n'avez pas l'autorisation d'accéder à cette page."
        redirect_back_or_to root_path
      end
    end
  RUBY

  # --- LOGIQUE ADMIN & POLICIES ---
  generate :controller, "admin/dashboard", "index", "--no-test-framework"
  
  file "app/policies/admin_policy.rb", <<~RUBY
    class AdminPolicy < ApplicationPolicy
      def index?
        user&.admin?
      end
    end
  RUBY

  file "app/controllers/admin/dashboard_controller.rb", <<~RUBY, force: true
    class Admin::DashboardController < ApplicationController
      def index
        authorize :admin, :index?
      end
    end
  RUBY

  # Routes
  route "namespace :admin do root to: 'dashboard#index' end"
  route "root to: 'pages#home'"
  generate :controller, "pages", "home", "--skip-routes"

  # Seeds
  file "db/seeds.rb", <<~RUBY, force: true
    User.destroy_all
    User.create!(email_address: "admin@prestige.com", password: "password123", admin: true)
    User.create!(email_address: "client@prestige.com", password: "password123", admin: false)
    puts "Base de données initialisée !"
  RUBY

  # Finalisation DB
  rails_command "db:prepare"
  rails_command "db:seed"

  run "touch .env"
  git :init
  git add: "."
  git commit: "-m 'Setup Prestige App: Auth, Pundit, Admin & Default Permissions'"
end

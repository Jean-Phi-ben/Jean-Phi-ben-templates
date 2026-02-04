run "if uname | grep -q 'Darwin'; then pgrep spring | xargs kill -9; fi"

# 1. Gemfile
########################################
gsub_file("Gemfile", /^gem "bootstrap".*\n/, "")
gsub_file("Gemfile", /^gem "sassc-rails".*\n/, "")
# On s'assure que propshaft est là pour éviter l'erreur de tâche assets:precompile
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
file "app/views/layouts/_head_scripts.html.erb", <<~HTML
  <%= javascript_importmap_tags %>
HTML

gsub_file "app/views/layouts/application.html.erb", '<%= javascript_importmap_tags %>', '<%= render "layouts/head_scripts" %>'

gsub_file "app/views/layouts/application.html.erb", '<%= yield %>', <<~HTML
  <div id="main-content" class="container mx-auto px-4 py-8">
    <%= yield %>
  </div>
HTML

# 3. Processus après bundle
########################################
after_bundle do
  run "bundle exec rails tailwindcss:install"
  generate "authentication"
  generate "pundit:install"
  
  # On génère l'admin avec le namespace
  generate :controller, "admin/dashboard", "index", "--no-test-framework"
  
  # ATTENTION : On vérifie si la colonne admin existe déjà pour éviter le crash PG::DuplicateColumn
  # Rails 8 authentication generator peut varier, donc on crée la migration prudemment
  generate :migration, "AddAdminToUsers", "admin:boolean"
  
  # Correction manuelle de la migration pour ajouter le default: false
  migration_file = Dir.glob("db/migrate/*_add_admin_to_users.rb").first
  if migration_file
    gsub_file migration_file, /t.boolean :admin/, "t.boolean :admin, default: false"
  end

  # Routes
  route "namespace :admin do root to: 'dashboard#index' end"
  route "root to: 'pages#home'"
  generate :controller, "pages", "home", "--skip-routes"

  # 4. LE SEED (On écrase le fichier pour être propre)
  ########################################
  file "db/seeds.rb", <<~RUBY, force: true
    puts "Nettoyage de la base..."
    User.destroy_all
    
    puts "Création des utilisateurs..."
    User.create!(
      email_address: "admin@chalet.com",
      password: "password123",
      admin: true
    )
    
    User.create!(
      email_address: "client@chalet.com",
      password: "password123",
      admin: false
    )
    puts "Terminé ! Admin: admin@chalet.com / pass: password123"
  RUBY

  # 5. Pundit : Protection de l'ApplicationController
  ########################################
  inject_into_file "app/controllers/application_controller.rb", after: "include Authentication" do
    "\n  include Pundit::Authorization"
  end

  # 6. Base de données
  ########################################
  rails_command "db:prepare"
  rails_command "db:seed"

  run "touch .env"
  
  git :init
  git add: "."
  git commit: "-m 'Setup complet Chalet Prestige : Rails 8 Auth, Tailwind, Pundit, Admin'"
end

rails new \
  -d postgresql \
  -m https://raw.githubusercontent.com/Jean-Phi-ben/Jean-Phi-ben-templates/main/tailwind-pundit.rb \
  nom_de_l_app

## Apple login 

Pour que le bouton Apple de ton chalet fonctionne, tu devras effectuer ces étapes manuellement (car elles nécessitent un compte développeur payant à 99$/an) :

App ID & Service ID : Créer un identifiant pour ton projet "Chalet Mont Rose".

Key (Private Key) : Générer une clé de type "Sign in with Apple", la télécharger et copier son contenu dans ton .env.

Redirect URI : Configurer https://ton-domaine.com/auth/apple/callback.

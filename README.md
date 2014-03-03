redmineinstaller
================

Very basic Redmine Installer

Utilizes vagrant although I'm still learning how to use it.

Just vagrant up a Ubuntu Precise box(although it may not matter really what version of ubuntu)
Modify the redmine_installer.sh and change all the user/pass and stuff in there(should be able to just sed or use vim/emacs to do it)
Then bash /vagrant/redmine_installer.sh


Should get you setup. Does not setup https yet and by default sets up sendgrid which you may not want so you will have to remove it from
config/environments/production.rb if you don't want it

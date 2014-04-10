#!/usr/bin/env bash

# Assumptions:
# * Ubuntu
# * postgres db
#
# Things to change in this file(by using sed or whatever is probably best)
#  * redmine_db_pass - Change to whatever you want your database password to be
#  * redmine_db_user - Change to whatever you want the db user to be
#  * redmine_db - Change to whatever you want the db name to be
#  * redmine.localdomain - Change to your hostname domain
#  * sendgrid_auth_name
#  * sendgrid_auth_password

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Necessary System Packages
sudo apt-get install -y git postgresql imagemagick vim libpq-dev libmagickwand-dev libcurl4-openssl-dev apache2-threaded-dev libapr1-dev libaprutil1-dev curl apache2-mpm-worker

# Set the hostname of this system
sudo hostname redmine.localdomain
echo $(hostname) | sudo tee /etc/hostname
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $(hostname)/" /etc/hosts

# Download and install redmine to /var/www/redmine
# Will checkout 2.4-stable
cd /var/www
sudo git clone -b 2.4-stable https://github.com/redmine/redmine
cd redmine
sudo chown -R $(whoami): /var/www/redmine

# Setup the database
sudo -u postgres psql <<EOF
CREATE ROLE redmine_db_user LOGIN ENCRYPTED PASSWORD 'redmine_db_pass' NOINHERIT VALID UNTIL 'infinity';
EOF
# This creates the database. I don't know postgres enough to know why I had to deviate
# from the redmine docs and do the createdb command and had to specify -T template0 because
# of some encoding error
sudo -u postgres createdb -E UTF8 --locale=en_US.UTF-8 redmine_db -O redmine_db_user -T template0

# Configure Database Connection
cat > config/database.yml <<EOF
production:
    adapter: postgresql
    database: redmine_db
    host: localhost
    username: redmine_db_user
    password: redmine_db_pass
    encoding: utf8
    schema_search_path: public
EOF

# Setup Ruby 2.0.0
# Not sure if you can use a newer version of ruby or not, redmine docs say
# 1.9.2, 1.9.3, 2.0.0
curl -sSL https://get.rvm.io | sudo bash -s stable --ruby=2.0.0

# Just really make sure it is installed
sudo rvm install 2.0.0

# And activate rvm ruby 2.0.0
rvm 2.0.0

sudo addgroup $(whoami) rvm
echo ". /etc/profile.d/rvm.sh" >> ~/.bashrc
echo ". /etc/profile.d/rvm.sh" |sudo tee -a /root/.bashrc
. /etc/profile.d/rvm.sh

# Install bundler and gem bundles
rvmsudo gem install bundler
# Email setup with sendgrid
cat > Gemfile.local <<EOF
# Gemfile.local
gem 'mail'
gem 'json'
gem 'sendgrid'
gem 'passenger'
EOF
bundle install --path vendor/bundle --without development test

# Generate Secret token
bundle exec rake generate_secret_token

# Create DB Structure
RAILS_ENV=production bundle exec rake db:migrate

# Load Initial Data
RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data

# Setup permissions
mkdir -p tmp tmp/pdf public/plugin_assets repos/git_repos
sudo chown -R www-data:www-data files log tmp public/plugin_assets repos/git_repos
sudo chmod -R 755 files log tmp public/plugin_assets repos/git_repos

# Install the new gems for sendgrid
rvmsudo bundle install

# Config for sendgrid
# Should drop the config in at the end of the config
sed -i 's/^end//' config/environments/production.rb
cat >> config/environments/production.rb <<EOF
  ActionMailer::Base.smtp_settings = {
    :address        => 'smtp.sendgrid.net',
    :port           => '587',
    :authentication => :plain,
    :user_name      => 'sendgrid_auth_name',
    :password       => 'sendgrid_auth_password',
    :domain         => 'redmine.localdomain'
  }
  ActionMailer::Base.delivery_method = :smtp
end
EOF

# Passenger setup
echo "Fusion Passenger will now be installed through a semi-automated installer"
echo "The apache config files should already be modified for you so you shouldn't have to do any config changes like the installer asks"
echo "The only thing you need to do is unselect python from the languages you are interested in and press enter a few times"
read -p "Press enter when you are ready"
rvmsudo vendor/bundle/ruby/2.0.0*/gems/passenger-*/bin/passenger-install-apache2-module
sudo service apache2 restart

# Setup of the apache config for passenger
cat > /tmp/passenger.cfg <<EOF
   LoadModule passenger_module $(pwd)/$(ls vendor/bundle/ruby/2.0.0/gems/passenger-*/buildout/apache2/mod_passenger.so)
   <IfModule mod_passenger.c>
     PassengerRoot $(pwd)/$(ls -d vendor/bundle/ruby/2.0.0/gems/passenger-*)
     PassengerDefaultRuby $(ls $GEM_HOME/wrappers/ruby)
   </IfModule>
EOF
cat /tmp/passenger.cfg /etc/apache2/sites-available/default | sudo tee /etc/apache2/sites-available/default

sudo sed -i 's/<\/VirtualHost>//' /etc/apache2/sites-available/default
sudo sed -i 's%DocumentRoot.*%DocumentRoot /var/www/redmine/public%' /etc/apache2/sites-available/default
cat | sudo tee -a /etc/apache2/sites-available/default <<EOF
      <Directory /var/www/redmine/public>
         # This relaxes Apache security settings.
         AllowOverride all
         # MultiViews must be turned off.
         Options -MultiViews
      </Directory>
</VirtualHost>
EOF


echo "Should now have redmine installed"
echo "Visit http://localhost to view your site"
echo "If you want to import data from a different installation then you will want to do the following:"
echo "dropdb -h localhost -U redmine_db_user redmine_db"
echo "sudo -u postgres createdb -E UTF8 --locale=en_US.UTF-8 redmine_db -O redmine_db_user -T template0"
echo "pg_restore --verbose --clean --no-acl --no-owner -h localhost -U redmine_db_user -d redmine_db /path/to/db.dump"
echo "RAILS_ENV=production bundle exec rake db:migrate"

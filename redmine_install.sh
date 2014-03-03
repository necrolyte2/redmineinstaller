#!/usr/bin/env bash

# Assumptions:
# * Ubuntu
# * postgres db
#
# Things to change in this file(by using sed or whatever is probably best)
#  * redmine_db_pass - Change to whatever you want your database password to be
#  * redmine_db_user - Change to whatever you want the db user to be
#  * redmine_db - Change to whatever you want the db name to be
#  * redmine.localdomain - Change to your hostname
#  * yourdomain.com
#  * sendgrid_auth_name
#  * sendgrid_auth_password

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install Necessary System Packages
sudo apt-get install -y git postgresql imagemagick vim libpq-dev libmagickwand-dev \
libcurl4-openssl-dev apache2-threaded-dev libapr1-dev libaprutil1-dev

# Set the hostname of this system
sudo hostname redmine.localdomain
echo $(hostname) | sudo tee /etc/hostname

# Download and install redmine to /var/www/redmine
# Will checkout 2.4-stable
cd /var/www
git clone -b 2.4-stable https://github.com/redmine/redmine
cd redmine

# Setup the database
sudo -u postgres psql <<EOF
CREATE ROLE redmine LOGIN ENCRYPTED PASSWORD 'redmine_db_pass' NOINHERIT VALID UNTIL 'infinity';
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

# Install bundler and gem bundles
sudo gem install bundler
sudo bundle install --without development test

# Generate Secret token
rake generate_secret_token

# Create DB Structure
RAILS_ENV=production rake db:migrate

# Load Initial Data
RAILS_ENV=production REDMINE_LANG=en rake redmine_db:load_default_data

# Setup permissions
mkdir -p tmp tmp/pdf public/plugin_assets repos/git_repos
sudo chown -R www-data:www-data files log tmp public/plugin_assets repos/git_repos
sudo chmod -R 755 files log tmp public/plugin_assets

# Email setup with sendgrid
cat > Gemfile.local <<EOF
# Gemfile.local
gem 'mail'
gem 'json'
gem 'sendgrid'
gem 'passenger'
EOF

# Install the new gems for sendgrid
sudo bundle install

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
    :domain         => 'yourdomain.com'
  }
  ActionMailer::Base.delivery_method = :smtp
end
EOF

# Setup of the apache config for passenger
sudo sed -i 's/<\/VirtualHost>//' /etc/apache2/sites-available/default
sudo sed -i 's%DocumentRoot.*%DocumentRoot /var/www/redmine/public%' default
sudo cat >> /etc/apache2/sites-available/default <<EOF
      <Directory /var/www/redmine/public>
         # This relaxes Apache security settings.
         AllowOverride all
         # MultiViews must be turned off.
         Options -MultiViews
      </Directory>
   </VirtualHost>
EOF
sudo ln -s ~/redmine-install /var/www/redmine-install

# Passenger setup
echo "Fusion Passenger will now be installed through a semi-automated installer"
echo "The apache config files should already be modified for you so you shouldn't have to do any config changes like the installer asks"
echo "The only thing you need to do is unselect python from the languages you are interested in and press enter a few times"
read -p "Press enter when you are ready"
sudo /usr/local/rvm/gems/ruby-2.0.0*/gems/passenger-*/bin/passenger-install-apache2-module
sudo service apache2 restart

echo "Should now have redmine installed"
echo "Visit http://localhost to view your site"
echo "If you want to import data from a different installation then you will want to do the following:"
echo "dropdb -h localhost -U redmine_db_user redmine_db"
echo "sudo -u postgres createdb -E UTF8 --locale=en_US.UTF-8 redmine_db -O redmine_db_user -T template0"
echo "pg_restore --verbose --clean --no-acl --no-owner -h localhost -U redmine_db_user -d redmine_db /path/to/db.dump"

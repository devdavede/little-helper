### PLEASE - UNDERSTAND WHAT THIS SCRIPT DOES BEFORE RUNNING ###
### THIS IS MY LITTLE HELPER TO SETUP A FRESH UBUNTU ENVIRONMENT ###
### CHECK THE CALLS OF create_vhost() AND ADD YOUR OWN DOMAINS ###
### RUN THIS SCRIPT FROM YOUR LOCAL MACHINE ###

#!/bin/bash

create_vhost() {
    local SITE_NAME="$1"
    local DOC_ROOT="$2"
    local LOG_DIR="$3"

    ssh "$USERNAME@$DOMAIN" "bash -s" <<ENDSSH
SITE_NAME="$SITE_NAME"
DOC_ROOT="$DOC_ROOT"
LOG_DIR="$LOG_DIR"
CONF_FILE="/etc/apache2/sites-available/\$SITE_NAME.conf"

# Ensure document root exists
sudo mkdir -p "\$DOC_ROOT"
sudo touch "\$DOC_ROOT/index.html"
sudo chown -R www-data:www-data "\$DOC_ROOT"

# Write Apache virtual host file
sudo tee "\$CONF_FILE" > /dev/null <<EOL
<VirtualHost *:80>
    ServerName \$SITE_NAME
    ServerAlias www.\$SITE_NAME

    DocumentRoot \$DOC_ROOT

    ErrorLog "\$LOG_DIR/\$SITE_NAME.error.log"
    CustomLog "\$LOG_DIR/\$SITE_NAME.access.log" combined

    <Directory \$DOC_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL

# Enable site and reload Apache
sudo a2ensite "\$(basename "\$CONF_FILE")"
sudo systemctl reload apache2

# Obtain SSL certificate
sudo certbot --apache -d "$SITE_NAME" --non-interactive --agree-tos --email certbot@$DOMAIN --no-eff-email
ENDSSH
}

### START HERE ###

### ASK FOR VARIABLES
echo "Auto-Setup Ubuntu Server and install packages"
echo "Will ask for root password sometimes (till passwordless login is set up)"
echo
read -p "IP or FQDN for remote host: " DOMAIN
read -p "Root username: " ROOT_USERNAME
read -p "New user to create (username) - will have sudo privileges: " USERNAME
read -sp "Password for user $USERNAME: " PASSWORD
echo

### REMOVE OLD KNOWN_HOSTS FOR DOMAIN
ssh-keygen -R $DOMAIN

# Copy SSH keys for root
ssh-copy-id "$ROOT_USERNAME@$DOMAIN"

# Update & upgrade
ssh "$ROOT_USERNAME@$DOMAIN" "sudo apt update -y && sudo apt upgrade -y"

# Create user $USERNAME with sudo
ssh "$ROOT_USERNAME@$DOMAIN" "sudo adduser --disabled-password --gecos '' $USERNAME"
ssh "$ROOT_USERNAME@$DOMAIN" "sudo usermod -aG sudo $USERNAME"
ssh "$ROOT_USERNAME@$DOMAIN" "echo '$USERNAME ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$USERNAME"
ssh "$ROOT_USERNAME@$DOMAIN" "sudo chmod 440 /etc/sudoers.d/$USERNAME"

# Set password for $USERNAME interactively

ssh "$ROOT_USERNAME@$DOMAIN" "echo '$USERNAME:$PASSWORD' | chpasswd"
# We don't need password anymore - securely unset variable
unset PASSWORD

# Copy SSH keys for $USERNAME
ssh-copy-id "$USERNAME@$DOMAIN"

# Disable password & $ROOT_USERNAME SSH login
ssh "$ROOT_USERNAME@$DOMAIN" "
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.\$(date +%F_%T)
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo echo \"ChallengeResponseAuthentication no\" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd
"

# Install IPTables & allow web traffic
ssh "$USERNAME@$DOMAIN" "
sudo apt install iptables iptables-persistent -y
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
"

# Install Apache
ssh "$USERNAME@$DOMAIN" "
sudo apt install apache2 -y
sudo systemctl start apache2
sudo systemctl enable apache2
"

# Install Certbot
ssh "$USERNAME@$DOMAIN" "sudo apt install certbot python3-certbot-apache -y"

# Create virtual hosts + SSL
create_vhost "example.com" "/var/www/example.com" "/var/log/apache2"

# Install PostgreSQL
ssh "$USERNAME@$DOMAIN" "
sudo apt install postgresql postgresql-contrib -y
sudo systemctl start postgresql
sudo systemctl enable postgresql
"

ssh "$USERNAME@$DOMAIN" '
  grep -q "ServerName" /etc/apache2/apache2.conf || echo "ServerName 127.0.0.1" | sudo tee -a /etc/apache2/apache2.conf > /dev/null
'

ssh "$USERNAME@$DOMAIN" "
sudo reboot
"

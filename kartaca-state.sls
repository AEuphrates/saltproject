# kartaca-state.sls

{% set kartaca = salt['pillar.get']('kartaca', {}) %}
{% set nginx = salt['pillar.get']('nginx', {}) %}
{% set mysql = salt['pillar.get']('mysql', {}) %}

# Create kartaca user
create_kartaca_user:
  user.present:
    - name: {{ kartaca.user }}
    - uid: {{ kartaca.uid }}
    - gid: {{ kartaca.gid }}
    - home: {{ kartaca.home }}
    - shell: {{ kartaca.shell }}
    - password: {{ kartaca.password }}
    - unless: 'getent passwd {{ kartaca.user }}'

# Grant sudo privileges to kartaca user
grant_sudo_privileges:
  cmd.run:
    - name: 'echo "{{ kartaca.user }} ALL=(ALL) NOPASSWD: /usr/bin/apt" > /etc/sudoers.d/{{ kartaca.user }}'
    - unless: 'grep -q "{{ kartaca.user }} ALL=(ALL) NOPASSWD: /usr/bin/apt" /etc/sudoers.d/{{ kartaca.user }}'

    # For CentOS
    - name: 'echo "{{ kartaca.user }} ALL=(ALL) NOPASSWD: /usr/bin/yum" >> /etc/sudoers.d/{{ kartaca.user }}'
    - unless: 'grep -q "{{ kartaca.user }} ALL=(ALL) NOPASSWD: /usr/bin/yum" /etc/sudoers.d/{{ kartaca.user }}'

# Set server timezone to Istanbul
set_timezone:
  timezone.system:
    - name: Europe/Istanbul

# Enable IP forwarding permanently
enable_ip_forwarding:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1
    - unless: 'sysctl -n net.ipv4.ip_forward | grep -q 1'

# Install necessary packages
install_necessary_packages:
  pkg.installed:
    - pkgs:
      - htop
      - tcptraceroute
      - iputils
      - dnsutils
      - sysstat
      - mtr
    - unless: 'dpkg-query -W htop tcptraceroute iputils-ping dnsutils sysstat mtr'

# Add Hashicorp repository and install Terraform
install_terraform:
  cmd.run:
    - name: |
        curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
        sudo apt-get update && sudo apt-get install terraform=1.6.4
    - unless: 'terraform -v | grep -q "1.6.4"'

# Add host entries to /etc/hosts
add_host_entries:
  file.append:
    - name: /etc/hosts
    - text: '{{ item }} kartaca.local'
    - require_in:
      - user: create_kartaca_user
    - unless: 'grep -q "{{ item }} kartaca.local" /etc/hosts'
  for_loop:
    - items: '192.168.168.128 192.168.168.129 192.168.168.130 192.168.168.131 192.168.168.132 192.168.168.133 192.168.168.134 192.168.168.135 192.168.168.136 192.168.168.137 192.168.168.138 192.168.168.139 192.168.168.140 192.168.168.141 192.168.168.142'

{% if grains['os_family'] == 'RedHat' %}

# On CentOS server

# Install Nginx
install_nginx:
  pkg.installed:
    - name: nginx
    - unless: 'rpm -q nginx'

# Configure Nginx to start automatically
nginx_autostart:
  service.running:
    - name: nginx
    - enable: True
    - unless: 'systemctl is-enabled nginx'

# Install necessary PHP packages
install_php_packages:
  pkg.installed:
    - pkgs:
      - php
      - php-fpm
      - php-mysqlnd
    - unless: 'dpkg-query -W php php-fpm php-mysqlnd'

# Download WordPress archive file
download_wordpress:
  cmd.run:
    - name: 'curl -o /tmp/wordpress.tar.gz https://wordpress.org/latest.tar.gz'
    - unless: 'test -e /tmp/wordpress.tar.gz'

# Unpack WordPress archive
unpack_wordpress:
  cmd.run:
    - name: 'tar -xzvf /tmp/wordpress.tar.gz -C /var/www/'
    - unless: 'test -e /var/www/wordpress'

# Configure Nginx to reload on update of nginx.conf
configure_nginx_reload:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf
    - template: jinja
    - require:
      - pkg: install_nginx
    - watch_in:
      - cmd: unpack_wordpress

# Enter database details into wp-config.php
configure_wp_config:
  cmd.run:
    - name: |
        sed -i "s/database_name_here/{{ mysql.database }}/; s/username_here/{{ mysql.user }}/; s/password_here/{{ mysql.password }}/" /var/www/wordpress/wp-config-sample.php
        mv /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php
    - unless: 'grep -q "{{ mysql.database }}" /var/www/wordpress/wp-config.php'

# Fetch secret and keys from API
fetch_wordpress_keys:
  cmd.run:
    - name: 'curl -o /var/www/wordpress/wp-keys.php https://api.wordpress.org/secret-key/1.1/salt/'
    - unless: 'test -e /var/www/wordpress/wp-keys.php'

# Create self-signed SSL certificate
create_ssl_certificate:
  cmd.run:
    - name: 'openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout {{ nginx.ssl_key_path }} -out {{ nginx.ssl_certificate_path }} -subj "/C=US/ST=CA/L=City/O=Organization/CN=kartaca.local"'
    - unless: 'test -e {{ nginx.ssl_key_path }} && test -e {{ nginx.ssl_certificate_path }}'

# Manage Nginx configuration with Salt
manage_nginx_configuration:
  file.managed:
    - name: /etc/nginx/nginx.conf
    - source: salt://files/nginx.conf


# Create a cron job to stop and restart Nginx service on the first day of every month
nginx_cron_job:
  cron.present:
    - user: root
    - name: 'restart_nginx'
    - month: '1'
    - job: '/bin/systemctl restart nginx'

# Set up logrotate configuration for Nginx logs
nginx_logrotate:
  file.managed:
    - name: /etc/logrotate.d/nginx
    - source: salt://files/nginx.logrotate
    - template: jinja

{% elif grains['os_family'] == 'Debian' %}

# On Ubuntu server (continued)

# Install MySQL
install_mysql:
  pkg.installed:
    - name: mysql-server
    - unless: 'dpkg-query -W mysql-server'

# Configure MySQL to start automatically
mysql_autostart:
  service.running:
    - name: mysql
    - enable: True
    - unless: 'systemctl is-enabled mysql'

# Create MySQL database and user for WordPress
create_mysql_database:
  cmd.run:
    - name: |
        mysql -e "CREATE DATABASE IF NOT EXISTS {{ mysql.database }}; \
                   CREATE USER '{{ mysql.user }}'@'localhost' IDENTIFIED BY '{{ mysql.password }}'; \
                   GRANT ALL PRIVILEGES ON {{ mysql.database }}.* TO '{{ mysql.user }}'@'localhost'; \
                   FLUSH PRIVILEGES;"
    - unless: 'mysql -e "SHOW DATABASES;" | grep -q "{{ mysql.database }}"'

# Prepare cron job for MySQL database dump
mysql_backup_cron:
  cron.present:
    - user: root
    - name: 'mysql_backup'
    - minute: '0'
    - hour: '2'
    - job: '/usr/bin/mysqldump -u {{ mysql.user }} -p{{ mysql.password }} {{ mysql.database }} > /backup/{{ mysql.database }}_$(date +\%Y\%m\%d).sql'

{% endif %}

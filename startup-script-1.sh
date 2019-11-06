#!/bin/bash

# Installs apache and a custom homepage
yum install -y httpd

# Create a sample web page
cat <<EOF > /var/www/html/index.html
<html><body><h1>Hello World</h1>
<p>This page was created from a simple start up script!</p>
</body></html>
EOF

# Start httpd service
service httpd start

echo -e "10.28.196.11\tDB2CM01" >> /etc/hosts
echo -e "10.28.196.12\tDB2CM02" >> /etc/hosts
ip route add 10.11.1.0/24 via 10.11.1.1 dev eth1
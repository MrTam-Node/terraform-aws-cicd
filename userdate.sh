#!/bin/bash
# Install updates and packages
yum update -y
yum install -y httpd

# Start and enable the web server
systemctl start httpd
systemctl enable httpd

# Create a sample webpage
echo "<h1>Welcome to the Production Server!</h1>" > /var/www/html/index.html

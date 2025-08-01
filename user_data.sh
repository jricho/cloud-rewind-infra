#!/bin/bash
yum update -y
amazon-linux-extras install -y nginx1
systemctl enable nginx
systemctl start nginx

echo "<h1>Protected with Cloud Rewind</h1>" > /usr/share/nginx/html/index.html

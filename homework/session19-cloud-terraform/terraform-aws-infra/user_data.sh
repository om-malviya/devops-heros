#!/bin/bash
# Runs once on first boot of the Amazon Linux 2023 instance (cloud-init).
set -euxo pipefail

dnf install -y nginx

cat > /usr/share/nginx/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head><title>Session 19 - Terraform on AWS</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 10%;">
  <h1>Hello from Terraform!</h1>
  <p>Session 19 - Cloud &amp; Terraform in Action</p>
  <p>Student: Om Malviya</p>
  <p>Host: $(hostname -f)</p>
</body>
</html>
HTML

systemctl enable nginx
systemctl start nginx

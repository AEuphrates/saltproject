# kartaca-pillar.sls

kartaca:
  user: kartaca
  uid: 2023
  gid: 2023
  home: /home/krt
  shell: /bin/bash
  password: kartaca2023

nginx:
  ssl_certificate_path: /etc/nginx/ssl/kartaca.crt
  ssl_key_path: /etc/nginx/ssl/kartaca.key

mysql:
  database: wordpressdb
  user: wpuser
  password: wpuserpass

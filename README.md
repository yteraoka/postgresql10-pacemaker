PostgreSQL 10 サーバー3台を pacemaker でクラスタ化する

```
ssh-keygen -t rsa -b 2048 -P "" -f id_rsa
vagrant up
vagrant ssh db1
db1$ bash -x /vagrant/init.sh
```

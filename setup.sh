#!/bin/bash

yum -y install https://download.postgresql.org/pub/repos/yum/10/redhat/rhel-7-x86_64/pgdg-centos10-10-2.noarch.rpm
yum -y install postgresql10-server postgresql10-contrib pcs pacemaker

systemctl start firewalld
systemctl enable firewalld
firewall-cmd --add-service high-availability
firewall-cmd --add-service high-availability --permanent
firewall-cmd --add-service postgresql
firewall-cmd --add-service postgresql --permanent

systemctl start pcsd
systemctl enable pcsd

echo passwd | passwd hacluster --stdin

curl -sLo /usr/lib/ocf/resource.d/heartbeat/pgsql10 \
  https://raw.githubusercontent.com/ClusterLabs/resource-agents/master/heartbeat/pgsql
chmod 755 /usr/lib/ocf/resource.d/heartbeat/pgsql10

sed -i 's/resource-agent name="pgsql"/resource-agent name="pgsql10"/' \
  /usr/lib/ocf/resource.d/heartbeat/pgsql10

cp -a /usr/share/resource-agents/ocft/configs/pgsql{,10}
sed -i \
    -e 's/Agent pgsql$/Agent pgsql10/' \
    -e 's/^# pgsql$/# pgsql10/' \
       /usr/share/resource-agents/ocft/configs/pgsql10

cat <<EOF | sudo bash -c "cat > /var/lib/pgsql/copyWAL.sh"
#!/bin/bash

set -eu

src_path=\$1
src_filename=\$2
shift 2

my_fqdn=\$(hostname -f)
my_hostname=\$(hostname -s)

for dst in "\$@"
do
    dst_host=\${dst%%:*}
    dst_dir=\${dst##*:}

    if [ "\$dst_host" != "\$my_fqdn" -a "\$dst_host" != "\$my_hostname" ] ; then
        rsync -e ssh "\$src_path" \$dst_host:"\$dst_dir/\$src_filename"
    fi
done
EOF
chmod 755 /var/lib/pgsql/copyWAL.sh

install -o postgres -g postgres -m 0700 -d /var/lib/pgsql/10/archive

sed -i '/db/d' /etc/hosts
cat >> /etc/hosts <<EOF
192.168.33.10 primary
192.168.33.11 db1
192.168.33.12 db2
192.168.33.13 db3
192.168.33.14 standby
192.168.33.20 client
EOF

cat >> /etc/ssh/sshd_config <<EOF
Match User postgres
	AuthorizedKeysFile /etc/ssh/authorized_keys/%u
EOF

install -o root -g root -m 0755 -d /etc/ssh/authorized_keys
install -o root -g root -m 0644 /vagrant/id_rsa.pub /etc/ssh/authorized_keys/postgres
install -o postgres -g postgres -m 0700 -d /var/lib/pgsql/.ssh
install -o postgres -g postgres -m 0600 /vagrant/id_rsa /var/lib/pgsql/.ssh/id_rsa
install -o postgres -g postgres -m 0600 /dev/null /var/lib/pgsql/.ssh/config
echo "StrictHostKeyChecking no" > /var/lib/pgsql/.ssh/config

sudo systemctl restart sshd

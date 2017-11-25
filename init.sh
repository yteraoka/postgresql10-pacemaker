#!/bin/bash

sudo PGSETUP_INITDB_OPTIONS="--data-checksums -E utf8 --no-locale" \
  /usr/pgsql-10/bin/postgresql-10-setup initdb

cat <<EOF | sudo tee -a /var/lib/pgsql/10/data/postgresql.conf
listen_addresses = '*'
max_connections = 20
shared_buffers = 64MB
temp_buffers = 8MB
work_mem = 8MB
maintenance_work_mem = 32MB
wal_level = logical
synchronous_commit = on
archive_mode = on
archive_command = '/var/lib/pgsql/copyWAL.sh %p %f db1:/var/lib/pgsql/10/archive db2:/var/lib/pgsql/10/archive db3:/var/lib/pgsql/10/archive'
archive_timeout = 300s
max_wal_senders = 10
max_replication_slots = 10
track_commit_timestamp = on
hot_standby = on
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%a.log'
log_truncate_on_rotation = on
log_rotation_age = 1d
log_rotation_size = 0
log_min_duration_statement = 200
log_line_prefix = '%t user=%u, db=%d, remote=%r, pid=%p, xid=%x '
log_temp_files = 0
log_lock_waits = on
log_statement= 'ddl'
log_timezone = 'Japan'
deadlock_timeout = 1s
EOF

sudo systemctl start postgresql-10

sudo -iu postgres /usr/pgsql-10/bin/psql \
  -c "CREATE USER repl REPLICATION PASSWORD 'replication';"

echo "host replication repl 192.168.33.0/24 trust" \
 | sudo bash -c "cat >> /var/lib/pgsql/10/data/pg_hba.conf"

sudo systemctl reload postgresql-10

sudo -iu postgres ssh db2 mkdir /var/lib/pgsql/10/archive /var/lib/pgsql/10/tmpdir
sudo -iu postgres ssh db3 mkdir /var/lib/pgsql/10/archive /var/lib/pgsql/10/tmpdir

sudo -iu postgres ssh db2 /usr/pgsql-10/bin/pg_basebackup \
  -h db1 -U repl -D /var/lib/pgsql/10/data --progress
sudo -iu postgres ssh db3 /usr/pgsql-10/bin/pg_basebackup \
  -h db1 -U repl -D /var/lib/pgsql/10/data --progress

sudo pcs cluster auth db1 db2 db3 -u hacluster -p passwd
sudo pcs cluster setup --start --name pg10 db1 db2 db3
sudo pcs node standby db2 db3

sudo pcs cluster cib > cib.xml

cp cib.xml cib.xml.orig

# disable stonith, quorum
pcs -f cib.xml property set no-quorum-policy="ignore"
pcs -f cib.xml property set stonith-enabled="false"

# Master 用 VIP (replication traffic 用に別セグメントを用意する場合はもう一つ定義してグルーピングする)
pcs -f cib.xml resource create master-vip ocf:heartbeat:IPaddr2 \
  ip=192.168.33.10 cidr_netmask=24 nic=eth1 iflabel=master op monitor interval=5s

# replica へ接続するための VIP
pcs -f cib.xml resource create replica-vip ocf:heartbeat:IPaddr2 \
  ip=192.168.33.14 cidr_netmask=24 nic=eth1 iflabel=replica op monitor interval=5s

# ping でネットワークの疎通をチェック
# --clone を指定しているので clone として全 node で起動する
# また、create の次に指定した ping という名前に -clone が追加される
pcs -f cib.xml resource create ping ocf:pacemaker:ping \
  dampen=5s multiplier=100 host_list=8.8.8.8 --clone

# PostgreSQL resource 作成
# master ... と指定しているので create の次に指定した pgsql という名前に -master が追加される
# master 指定するこで Master/Slave resource となる (別途 pcs resource master ... とする方法もある)
# constraint で attribute に指定している pgsql-data はここで指定した pgsql という名前に -data が付いている
# (hogehoge という名前で作れば hogehoge-master や hogehoge-data となる)
pcs -f cib.xml resource create pgsql ocf:heartbeat:pgsql10 \
  pgctl="/usr/pgsql-10/bin/pg_ctl" \
  pgdata="/var/lib/pgsql/10/data" \
  psql="/usr/pgsql-10/bin/psql" \
  config="/var/lib/pgsql/10/data/postgresql.conf" \
  stop_escalate="5" \
  rep_mode="sync" \
  node_list="db1 db2 db3" \
  restore_command='/usr/bin/cp /var/lib/pgsql/10/archive/%f %p' \
  archive_cleanup_command='/usr/pgsql-10/bin/pg_archivecleanup /var/lib/pgsql/10/archive %r' \
  master_ip="192.168.33.10" \
  primary_conninfo_opt="keepalives_idle=60 keepalives_interval=5 keepalives_count=5" \
  repuser="repl" \
  restart_on_promote="true" \
  tmpdir="/var/lib/pgsql/10/tmpdir" \
  xlog_check_count="3" \
  crm_attr_timeout="5" \
  check_wal_receiver="true" \
  op monitor interval="11s" op monitor interval="10s" role="Master" \
  master master-max=1 master-node-max=1 clone-max=3 clone-node-max=1 notify=true target-role='Started'

# pgsql は ping の通る node でのみ実行
pcs -f cib.xml constraint location pgsql-master rule score=-INFINITY pingd lt 1 or not_defined pingd

# master-vip は pgsql の master node につくようにする
pcs -f cib.xml constraint colocation add master-vip with master pgsql-master INFINITY

# pgsql を promote したらその node で MasterGroup を起動させる
pcs -f cib.xml constraint order promote pgsql-master then start master-vip symmetrical=false score=INFINITY

# pgsql を demote したらその node では MasterGroup を停止さえる
pcs -f cib.xml constraint order demote pgsql-master then stop master-vip symmetrical=false score=0

# replica-vip は sync standby につける、sync standby が存在しなければ master につける
pcs -f cib.xml constraint location replica-vip rule score=200 pgsql-status eq HS:sync
pcs -f cib.xml constraint location replica-vip rule score=100 pgsql-status eq PRI
pcs -f cib.xml constraint location replica-vip rule score=-INFINITY not_defined pgsql-status
pcs -f cib.xml constraint location replica-vip rule score=-INFINITY pgsql-status ne HS:sync and pgsql-status ne PRI

# cib.xml を反映させる
sudo pcs cluster cib-push cib.xml

i=0
while : ; do
    i=$(($i + 1))
    started=$(sudo pcs status | grep -c "Started db1")
    echo -n "."
    if [ "$started" = "2" ] ; then
        echo ""
        echo "sudo pcs unstandby db2 db3"
        sudo pcs unstandby db2 db3
	break
    fi
    if [ $i -gt 120 ] ; then
        echo "couldn't get started"
        sudo pcs status
	exit 1
    fi
    sleep 2
done

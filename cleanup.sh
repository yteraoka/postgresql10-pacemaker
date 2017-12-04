#!/bin/bash

sudo pcs cluster destroy --all

for s in db1 db2 db3; do
  for d in data tmpdir archive; do
    sudo -iu postgres \
      ssh $s "rm -fr /var/lib/pgsql/10/$d; install -m 0700 -d /var/lib/pgsql/10/$d"
  done
done

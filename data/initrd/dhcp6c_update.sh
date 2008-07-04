#! /bin/sh

cat "$1" >>/etc/resolv.conf

echo -n >/tmp/dhcp6c_update.done


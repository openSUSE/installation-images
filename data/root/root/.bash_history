less -S /var/log/YaST2/y2log
vi /root/.yast2/logconf.ycp
tail --follow=name --retry /var/log/YaST2/y2log

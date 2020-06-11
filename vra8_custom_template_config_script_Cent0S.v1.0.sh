#!/bin/bash
# vRealize Automation 8.x vSphere Virtual Machine Static IP address template configuration
# Support Cent0S 7.8
# Support vRealize Automation 8.0、8.0.1、8.1
# Author: Xu
# Version：1.0
# Website: www.vmlab.org


###System Update###
yum update && yum upgrade

###Install cloud-init. ### 
yum install -y cloud-init

###Disable vmware customization for cloud-init. ###
sed -i 's/^disable_vmware_customization: false/disable_vmware_customization: true/g' /etc/cloud/cloud.cfg
###Setting datasouce is OVF only. ### 
sed -i '/^disable_vmware_customization: true/a\datasource_list: [OVF]' /etc/cloud/cloud.cfg
###Disalbe clean tmp folder. ### 
sed -i "s/\(^.*10d.*$\)/#\1/" /usr/lib/tmpfiles.d/tmp.conf
###Add After=dbus.service to vmtools. ### 
sed -i '/^After=vgauthd.service/a\After=dbus.service' /usr/lib/systemd/system/vmtoolsd.service
###eanble root and password login for ssh. ###
sed -i 's/^disable_root: 1/disable_root: 0/g' /etc/cloud/cloud.cfg
sed -i 's/^ssh_pwauth:   0/ssh_pwauth:   1/g' /etc/cloud/cloud.cfg
sed -i '/^disable_vmware_customization: true/a\network:' /etc/cloud/cloud.cfg
sed -i '/^network:/a\  config: disabled' /etc/cloud/cloud.cfg


###Disable cloud-init in first boot,we use vmware tools exec customization. ### 
touch /etc/cloud/cloud-init.disabled

###Create a runonce script for re-exec cloud-init. ###
cat <<EOF > /etc/cloud/runonce.sh
#!/bin/bash

if [ -e /tmp/guest.customization.stderr ]
then
  sudo rm -rf /etc/cloud/cloud-init.disabled
  sudo systemctl restart cloud-init.service
  sudo systemctl restart cloud-config.service
  sudo systemctl restart cloud-final.service
  sudo systemctl disable runonce
  sudo touch /tmp/cloud-init.success
fi

exit
EOF

###Create a runonce service for exec runonce.sh with system after reboot. ### 
cat <<EOF > /etc/systemd/system/runonce.service
[Unit]
Description=Run once
Requires=network-online.target
Requires=cloud-init-local.sevice
After=network-online.target
After=cloud-init-local.service

[Service]
###wait for vmware customization to complete, avoid executing cloud-init at the first startup.###
ExecStartPre=/bin/sleep 10
ExecStart=/etc/cloud/runonce.sh

[Install]
WantedBy=multi-user.target
EOF

###Create a cleanup script for build vRA template. ### 
cat <<EOF > /etc/cloud/template_clean.sh
#!/bin/bash

#Clear audit logs
if [ -f /var/log/audit/audit.log ]; then
cat /dev/null > /var/log/audit/audit.log
fi
if [ -f /var/log/wtmp ]; then
cat /dev/null > /var/log/wtmp
fi
if [ -f /var/log/lastlog ]; then
cat /dev/null > /var/log/lastlog
fi

#Cleanup persistent udev rules
if [ -f /etc/udev/rules.d/70-persistent-net.rules ]; then
rm /etc/udev/rules.d/70-persistent-net.rules
fi

#Cleanup /tmp directories
rm -rf /tmp/*
rm -rf /var/tmp/*

#Cleanup current ssh keys
#rm -f /etc/ssh/ssh_host_*

#cat /dev/null > /etc/hostname

#Cleanup apt
yum clean all

#Clean Machine ID

truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

#Clean Cloud-init
cloud-init clean --logs --seed

#Disabled Cloud-init
touch /etc/cloud/cloud-init.disabled
rm -rf /var/run/cron.reboot
#Cleanup shell history
history -cw
EOF


###Change script execution permissions. ### 
chmod +x /etc/cloud/runonce.sh /etc/cloud/template_clean.sh

###Reload runonce.service. ### 
systemctl deamon-reload

###Enable runonce.service on system boot. ### 
systemctl enable runonce.service

###Clean template configure the history. ### 
/etc/cloud/template_clean.sh

###Shutdown template OS. ###
shutdown -h now

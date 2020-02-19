#!/bin/bash
# Adapted from https://medium.com/sausheong/setting-up-a-raspberry-pi-4-as-an-development-machine-for-your-ipad-pro-3813f872fccc
# create a directory to represent the gadget
cd /sys/kernel/config/usb_gadget/ # must be in this dir
mkdir -p pi4
cd pi4 # the USB vendor and product IDs are issued by the USB-IF
# each USB gadget must be identified by a vendor and
# product ID
echo 0x1d6b > idVendor # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadgetmkdir -p strings/0x409 # set it up as English
# The configuration below is arbitrary
mkdir strings/0x409
echo "1234567890abcdef" > strings/0x409/serialnumber
echo "Chang Sau Sheong" > strings/0x409/manufacturer
echo "Pi4 USB Desktop" > strings/0x409/product# create a configuration
mkdir -p configs/c.1
# create a function
# ECM is the function name, and usb0 is arbitrary string
# that represents the instance name
mkdir -p functions/ecm.usb0 # associate function to configuration
ln -s functions/ecm.usb0 configs/c.1/ # bind the gadget to UDC
ls /sys/class/udc > UDC # start up usb0
ifup usb0 
# start dnsmasq
service dnsmasq restart

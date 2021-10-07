#!/bin/sh

home_dir="/home/piku"
user="piku"
group="www-data"
ssh_user="root"

install -d -m 0777 -o $user -g $group "${home_dir}" # create directory with permissions







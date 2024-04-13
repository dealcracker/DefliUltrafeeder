#!/bin/bash
# install the Defli Ultrafeeder
# Copyright (c) 2024 dealcracker
#

#enforce sudo
if ! [[ $EUID = 0 ]]; then
    echo "Please run this script with 'sudo'..."
    exit 1
fi

#stop and remove readsb service
systemctl stop readsb > /dev/null 2>&1
systemctl disable readsb > /dev/null 2>&1
rm -f /lib/systemd/system/readsb.service > /dev/null 2>&1
systemctl daemon-reload > /dev/null 2>&1
systemctl reset-failed > /dev/null 2>&1

#change to user's home dir
user_dir=$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)
cd $user_dir

#get the user name
user_name=sudo who am i | awk '{print $1}'
current_dir=$(pwd)

#stop and remove any running node-res service
systemctl stop nodered > /dev/null 2>&1
systemctl disable nodered > /dev/null 2>&1
rm -f /lib/systemd/system/nodered.service > /dev/null 2>&1

#remove any existing node-red installation directories
rm -fr /root/.node-red > /dev/null 2>&1
rm -fr $current_dir/.node-red > /dev/null 2>&1


#Prompt user for the Ground Station information
echo "Find your time zone (Country/Region) on this website: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones"
read -p "Time Zone (ie America/New_York):  " timeZone
echo
echo "Enter the geogrphical coordinates (decimal) and elevation (meters) of your Defli ground station"
read -p "Latitude:  " latitude
read -p "Longitude: " longitude
read -p "Enter Elevation (m): " elevation 
echo
echo "Go to defli-wallet.com to find your unique Ground Station Bucket ID"
read -p "Enter Your Ground Station Bucket ID: " bucket
echo

#REMOVE TEMP TEST
# timeZone="America/New_York"
# latitude="39.0"
# longitude="-84.0"
# elevation="280"
# bucket="dealcracker"

#Make bucket lowercase
bucket="$(tr [A-Z] [a-z] <<< "$bucket")"

#check GS ID length
if [ "${#bucket}" -lt 3 ]; then
  echo "Error: Ground Station Bucket ID is too short."
  echo "Aborting installation"
  exit 1
fi

#check latitutde
if (( $(echo "$latitude < -90.0" | bc -l) )) && (( $(echo "$latitude > 90.0" | bc -l) )); then 
  echo "The latitude value you entered is invalid. Aborting installation."
  exit 1
fi

#check longitute.
if (( $(echo "$Longitude < -180.0" | bc -l) )) && (( $(echo "$Longitude > 180.0" | bc -l) )); then 
  echo "The Longitude value you entered is invalid. Aborting installation."
  exit 1
fi

echo
echo "============ Utrafeeder ==============="
echo "Installing the Utrafeeder connector for Defli" 

#test if localhost is reachable
  echo "Determining local IP address..."
  
  # get the eth0 ip address
  ip_address=$(ip addr show eth0 | awk '/inet / {print $2}' | cut -d'/' -f1)
  #Check if eth0 is up and has an IP address
  if [ -n "$ip_address" ]; then
    echo "Using wired ethernet IP address: $ip_address"
  else
    # Get the IP address of the Wi-Fi interface using ip command
    ip_address=$(ip addr show wlan0 | awk '/inet / {print $2}' | cut -d'/' -f1)
    if [ -n "$ip_address" ]; then
      echo "Using wifi IP address: $ip_address"
    else
      ip_address=""
    fi
  fi

# Update the package list
echo ""
echo "Updating package list..."
apt-get -qq update -y

echo ""
echo "Removing any existing dockers..."

#clean up any previous dockers
docker stop prometheus > /dev/null 2>&1
docker stop ultrafeeder > /dev/null 2>&1
docker stop grafana > /dev/null 2>&1
docker rm ultrafeeder > /dev/null 2>&1
docker rm prometheus > /dev/null 2>&1
docker rm grafana > /dev/null 2>&1
docker container prune -f > /dev/null 2>&1
rm -fr /opt > /dev/null 2>&1

echo ""
echo "Intalling Ultrafeeder..."

docker network create -d bridge grafana_default

#new opt directory
mkdir -p -m 777 /opt/adsb
cd /opt/adsb

#get the default docker compose file
rm -f /opt/adsb/docker-compose.yml
wget https://raw.githubusercontent.com/dealcracker/DefliUltrafeeder/master/ultrafeeder-docker-compose.yml 
mv ultrafeeder-docker-compose.yml /opt/adsb/docker-compose.yml

#get the default .env file
rm -f /opt/adsb/.env
wget https://raw.githubusercontent.com/dealcracker/DefliUltrafeeder/master/env.txt 
mv env.txt /opt/adsb/.env

# updated the coordinates and IP in defaultFlows.json
original_line1="GS_LATITUDE"
new_line1=$latitude

original_line2="GS_LONGITUDE"
new_line2=$longitude

original_line3="GS_TIMEZONE"
new_line3=$timeZone

original_line4="GS_BUCKET"
new_line4=$bucket

original_line5="GS_ELEVATION"
new_line5=$elevation

original_line6="GS_PFIELD"
new_line6="password"

original_line7="GS_PWORD"
new_line7="glc_eyJvIjoiMTA4MjgwNiIsIm4iOiJzdGFjay04ODc4MjAtaG0tcmVhZC1kZWZsaS1kb2NrZXIiLCJrIjoiN2NXNjJpMDkyTmpZUWljSDkwT3NOMDh1IiwibSI6eyJyIjoicHJvZC11cy1lYXN0LTAifX0="

sed -i "s|$original_line1|$new_line1|g" "docker-compose.yml"
sed -i "s|$original_line2|$new_line2|g" "docker-compose.yml"
sed -i "s|$original_line3|$new_line3|g" "docker-compose.yml"
sed -i "s|$original_line5|$new_line5|g" "docker-compose.yml"

sed -i "s|$original_line1|$new_line1|g" ".env"
sed -i "s|$original_line2|$new_line2|g" ".env"
sed -i "s|$original_line3|$new_line3|g" ".env"
sed -i "s|$original_line4|$new_line4|g" ".env"
sed -i "s|$original_line5|$new_line5|g" ".env"

#compose the ultrafeeder container
docker compose up -d ultrafeeder

#create grafana container
cd /
sudo mkdir -p -m777 /opt/grafana/grafana/appdata /opt/grafana/prometheus/config /opt/grafana/prometheus/data
cd /opt/grafana

#get the grafana compose yml file
rm -f /opt/grafana/docker-compose.yml 
wget https://raw.githubusercontent.com/dealcracker/DefliUltrafeeder/master/grafana-docker-compose.yml 
mv grafana-docker-compose.yml /opt/grafana/docker-compose.yml 

docker compose up -d

#get the ultrafeeder container IP
original_line8="GS_ULTRAFEEDER_IP"
new_line8=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ultrafeeder)

echo "Ultrafeeder container IP: $new_line8"

#prepare promethius.yml
cd /opt/grafana/prometheus/config/
rm -f //opt/grafana/prometheus/config/prometheus.yml
wget https://raw.githubusercontent.com/dealcracker/DefliUltrafeeder/master/prometheus.yml

sed -i "s|$original_line4|$new_line4|g" "prometheus.yml"
sed -i "s|$original_line6|$new_line6|g" "prometheus.yml"
sed -i "s|$original_line7|$new_line7|g" "prometheus.yml"
sed -i "s|$original_line8|$new_line8|g" "prometheus.yml"

#stop prometheus and re compose
docker stop prometheus
docker compose up -d

echo
echo "***** Installation Script Complete *****"
echo
echo "Now navigate to:"
echo "http://localhost:3000/ this is your personal grafana console username:admin password:admin"
echo "Click "add your first data source" Click \"prometheus\""
echo "Under name enter- ultrafeeder Under URL enter- http://prometheus:9090/ or http://your-ip-address:9090/"
echo "Click save and test"
echo 
echo "If you get the green message you can click 'build dashboard'"
echo "In the box with title 'import via grafana.com' enter 18398 and press load"
echo "Select 'ultrafeeder' from the dropdown list"
echo "Click import"
echo "Your dashboard will populate"
echo
echo "If all is working you should see outputs here:"
echo "http://localhost:8080/ "
echo "http://localhost:8080/graphs1090/"
echo "http://localhost:9273/metrics/"
echo "http://localhost:9090/"
echo
echo "Note that if your browser is on a different machine, change 'localhost' to the device IP: $ip_address"
echo
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
echo "Go to https://defli-data.com/ to find your unique Ground Station ID"
read -p "Enter Your Ground Station ID: " bucket
echo

#Make bucket lowercase
bucket="$(tr [A-Z] [a-z] <<< "$bucket")"

#check GS ID length
if [ "${#bucket}" -lt 3 ]; then
  echo "Error: Ground Station ID is too short."
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

# Update the package list
echo ""
echo "Updating package list..."
apt-get -qq update -y

#Get local IP
echo "Determining local IP address..."
ip_address=$(ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}') 
echo
echo "Using local IP address: $ip_address"

#remove any previous dockers
echo ""
echo "Removing any existing dockers..."
#clean up any previous dockers
docker stop prometheus > /dev/null 2>&1
docker stop ultrafeeder > /dev/null 2>&1
docker stop grafana > /dev/null 2>&1
docker stop grafana-renderer-1  > /dev/null 2>&1
docker rm ultrafeeder > /dev/null 2>&1
docker rm prometheus > /dev/null 2>&1
docker rm grafana > /dev/null 2>&1
docker rm grafana-renderer-1  > /dev/null 2>&1
docker container prune -f > /dev/null 2>&1
rm -fr /opt > /dev/null 2>&1

echo ""
echo "Intalling Ultrafeeder..."

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

# prepare replacement values for key text
key_lat="GS_LATITUDE"
new_lat=$latitude

key_lon="GS_LONGITUDE"
new_lon=$longitude

key_tz="GS_TIMEZONE"
new_tz=$timeZone

key_bucket="GS_BUCKET"
new_bucket=$bucket

key_elev="GS_ELEVATION"
new_elev=$elevation

key_pfield="GS_PFIELD"
new_pfield="password"

key_pword="GS_PWORD"
new_pword="glc_eyJvIjoiMTA4MjgwNiIsIm4iOiJzdGFjay04ODc4MjAtaG0tcmVhZC1kZWZsaS1kb2NrZXIiLCJrIjoiN2NXNjJpMDkyTmpZUWljSDkwT3NOMDh1IiwibSI6eyJyIjoicHJvZC11cy1lYXN0LTAifX0="

key_ip_addr="LAN_IP"
new_ip_addr=$ip_address

#update the env file
sed -i "s|$key_lat|$new_lat|g" ".env"
sed -i "s|$key_lon|$new_lon|g" ".env"
sed -i "s|$key_tz|$new_tz|g" ".env"
sed -i "s|$key_elev|$new_elev|g" ".env"
sed -i "s|$key_bucket|$new_bucket|g" ".env"

#compose ultrafeeder
docker compose up -d

#create grafana container
cd /
sudo mkdir -p -m777 /opt/grafana/grafana/appdata /opt/grafana/prometheus/config /opt/grafana/prometheus/data
cd /opt/grafana

#get the grafana compose yml file
rm -f /opt/grafana/docker-compose.yml 
wget https://raw.githubusercontent.com/dealcracker/DefliUltrafeeder/master/grafana-docker-compose.yml 
mv grafana-docker-compose.yml /opt/grafana/docker-compose.yml 

#compose grafana 
docker compose up -d

#prepare promethius.yml
cd /opt/grafana/prometheus/config/
rm -f //opt/grafana/prometheus/config/prometheus.yml
wget https://raw.githubusercontent.com/dealcracker/DefliUltrafeeder/master/prometheus.yml

sed -i "s|$key_ip_addr|$new_ip_addr|g" "prometheus.yml"
sed -i "s|$key_pfield|$new_pfield|g" "prometheus.yml"
sed -i "s|$key_pword|$new_pword|g" "prometheus.yml"

#stop prometheus and compose prometheus
docker stop prometheus
docker compose up -d

echo
echo "*********** Installation Script Complete ***********"
echo
echo "Navigate to:"
echo "http://$ip_address:3000/ this is your personal grafana console username:admin password:admin"
echo
echo "Data Source"
echo "Click "add your first data source" Click \"prometheus\""
echo "Under name enter- ultrafeeder Under URL enter- http://$ip_address:9090/"
echo "Click save and test"
echo 
echo "Dashboard"
echo "If you get the green message you can click 'build dashboard'"
echo "In the box with title 'import via grafana.com' enter 18398 and press load"
echo "Select 'ultrafeeder' from the dropdown list"
echo "Click import"
echo "Your dashboard will populate"
echo
echo "If all is working you should see outputs here:"
echo "http://$ip_address:8080/              Tar1090 Map"
echo "http://$ip_address:8080/graphs1090/   Graphs1090 Graph"
echo "http://$ip_address:9273/metrics/      Ultrafeeder Metrics"
echo



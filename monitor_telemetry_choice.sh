#!/bin/bash

# --------------------------------------------------
#  GPIO Polling Script for Chasemapper Raspberry Pi
# --------------------------------------------------
# This bash script was written to read the GPIO pins on my in-vehicle Raspberry Pi and switch between
# telemetry modes for chasemapper when I press a button on my dash. I really only wrote it for me, and
# it works for me. I know that this isn't the most efficient solution, but it was quite a simple one.
# If you have stumbled onto this online, please note that this repository has
# NO WARRANTY WHATSOEVER, EXPRESS OR IMPLIED
#
# TELEMETRY SWITCHING
# -------------------
# The script detects a change in state of the TelemetryGPIO pin.
#
# If TelemetryGPIO is HIGH then radiosonde_auto_rx is selected.  The docker compose stack is taken down
# to disable horusdemodlib, and the docker container for radiosonde_auto_rx is started.
#
# If TelemetryGPIO is LOW then horusdemodlib is selected.  The docker container for radiosonde_auto_rx 
# is stopped and the docker compose stack is brought up to start horusdemodlib.
#
# Without furhter modification this script will only work on a Pi where radisonde_auto_rx and chasemapper
# are running in docker and horusdemodlib is running in docker compose from /home/{USER}/horusdemodlib/
#
# IMPORTANT: There are FIVE locations in this script where the path to the home directory are hardcoded.
# This means that anywhere you see /home/VK5CBM/ you must replace VK5CBM with YOUR USERNAME on your pi.
#
# RESTART CHASEMAPPER AFTER CHANGING MODES
# ----------------------------------------
# There is an option in this script to restart chasemapper after changing modes. This shuts down the
# chasemapper docker container, changes the default telemetry profile in the chasemapper config file
# and then restarts the chasemapper docker container. This saves the user from having to manually
# select the telemetry source in chasemapper.
# This will only work if the config file is located at /home/{USER}/chasemapper/horusmapper.cfg unless
# you edit that path where it is hardcoded in the script.
# To disable this function set restart_chasemapper_after_change to 0.
#
# SAFE SHUTDOWN
# -------------
# This script also executes a safe shutdown when the ShutdownGPIO pin is pulled low. 
# On my vehicle, the Pi is powered directly from the battery, rather than through the ignition switch.
# The shutdown GPIO pin is pulled low when the ignition is switched off.  The Pi is kept running by a
# 3 minute delay off timer on the power supply which allows adequate time for the shutdown to complete.
# 
# IMPORTANT: This script needs privileges to execute a shutdown.  Probably the easiest way to grant 
# these privileges is to use:
# chmod 4755 /sbin/shutdown
# Please note that this will grant ALL users the privileges to execute a shutdown.
#
# PLEASE NOTE THAT THE GPIO NUMBERS BELOW ARE *GPIO* NUMBERS NOT PIN NUMBERS!
# For example, GPIO23 is actually pin 16 on the 40 pin header, and GPIO24 is pin 18.

# Set GPIO pin to select telemetry type
TelemetryGPIO=24

# Set GPIO pin for shutdown command
ShutdownGPIO=23

# Restart Chasemapper in appropriate telemetry mode after changing modes?  This will likely cause chasemapper to forget history etc.
restart_chasemapper_after_change=1

# END OF CONFIGURATION

# Set working directory - this is required for docker compose to launch horusdemodlib properly
cd /home/VK5CBM/horusdemodlib

# Define color code constants for text output
BLACK='\033[0;30m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
LGREY='\033[0;37m'
DGREY='\033[1;30m'
LRED='\033[1;31m'
LGREEN='\033[1;32m'
YELLOW='\033[1;33m'
LBLUE='\033[1;34m'
LPURPLE='\033[1;35m'
LCYAN='\033[1;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color



# Set the LastValue variable to something non-binary so that it will be changed the first time the TelemetryGPIO pin is polled
LastValue=2

echo "${GREEN}---------------------------------------"
echo " POLLING FOR TELEMETRY TYPE ON GPIO" $TelemetryGPIO
echo "         AND SHUTDOWN SIGNAL ON GPIO" $ShutdownGPIO
echo "---------------------------------------${NC}"
echo ""

while true; do
   Timestamp=$( date '+%F_%H:%M:%S' )

# read the ShutdownGPIO pin and shutdown if neccesary
   ShutdownValue=$(pinctrl get $ShutdownGPIO | sed "s/^.*\(| hi \).*$/1/;s/^.*\(| lo \).*$/0/")
      if [ $ShutdownValue -eq 1 ]
      then
         # The Shutdown GPIO has gone LOW - Debounce for 3 seconds, and if still low then shutdown
         echo "$Timestamp Shutdown signal has gone low - Debouncing over 3 seconds before initiating shutdown"
         sleep 3
         if [ $ShutdownValue -eq $(pinctrl get $ShutdownGPIO | sed "s/^.*\(| hi \).*$/1/;s/^.*\(| lo \).*$/0/") ]
         then          
            shutdown now
         fi
      fi


# read the TelemetryGPIO pin input and do telemetry switching stuff
   CurrentValue=$(pinctrl get $TelemetryGPIO | sed "s/^.*\(| hi \).*$/1/;s/^.*\(| lo \).*$/0/")
   # Output the current pin status to the terminal along with a current timestamp - keep doing this over the same line.
   # THIS IS VERBOSE - DO NOT PIPE THIS OUTPUT TO A LOG FILE ON AN SD CARD AS IT WILL MAKE EXCESSIVE WRITES AN COULD CORRUPT THE MEDIA
   echo "\e[A\e[K$Timestamp $CurrentValue"

   if [ $LastValue != $CurrentValue ] 
   then
      # Wait 3 seconds and check if changed value is still correct
      sleep 3
      if [ $CurrentValue -eq $(pinctrl get $TelemetryGPIO | sed "s/^.*\(| hi \).*$/1/;s/^.*\(| lo \).*$/0/") ]
      then
         LastValue=$CurrentValue
         if [ $CurrentValue -eq 1 ]
         then
            echo "${PURPLE}State change detected - Telemetry GPIO is HIGH - Auto_RX is Selected${NC}"
            echo "Terminating horusdemodlib via docker-compose"
            cd /home/VK5CBM/horusdemodlib
            docker-compose down
            echo "Launching docker container for radiosonde_auto_rx..."
            docker start radiosonde_auto_rx &

            # If we want to auto-switch modes in chasemapper, then do that now by modifying the chasemapper config and restarting the docker container
            if [ $restart_chasemapper_after_change -eq 1 ]
            then
               echo "Restarting chasemapper in Auto_RX mode..."
               sed -i "s/\(default_profile *= *\).*/\11/" /home/VK5CBM/chasemapper/horusmapper.cfg
               docker restart chasemapper
            fi

            echo "${GREEN}----------------------------------"
            echo " BACK TO POLLING"
            echo "----------------------------------${NC}"
            echo ""
         else
            echo "${PURPLE}State change detected - Telemetry GPIO is LOW - Horus is Selected${NC}"
            echo "Terminating radiosonde_auto_rx..."
            docker stop radiosonde_auto_rx
            echo "Launching Horus Decoder via docker-compose..."
            cd /home/VK5CBM/horusdemodlib
            docker-compose up -d

            # If we want to auto-switch modes in chasemapper, then do that now by modifying the chasemapper config and restarting the docker container
            if [ $restart_chasemapper_after_change -eq 1 ]
            then
               echo "Restarting chasemapper in Horus mode..."
               sed -i "s/\(default_profile *= *\).*/\12/" /home/VK5CBM/chasemapper/horusmapper.cfg
               docker restart chasemapper
            fi

            echo "${GREEN}----------------------------------"
            echo " BACK TO POLLING"
            echo "----------------------------------${NC}"
            echo ""
         fi
      fi
   fi

done





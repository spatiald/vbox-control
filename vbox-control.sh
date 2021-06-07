#!/bin/bash
version="4.3"
# Ignore spaces as line breaks in for loop
IFS=$(echo -en "\n\b")
vboxScript="vbox-control"
vboxManageExe=$(which VBoxManage)
vboxUser="redteam"
virtualboxConfig="/etc/default/virtualbox"
vboxAutostartDB="/etc/vbox"
vboxAutostartConfig="/etc/vbox/autostart.cfg"
os=$(uname -a|egrep 'Linux|Ubuntu|Debian')
logFile="$vboxScript.log"
virtualboxVersion="$(VBoxManage --version)"
virtualboxVersionShort="$(echo $virtualboxVersion | cut -d"r" -f1)"
virtualboxVersionAvailable="$(curl -L -s "https://www.oracle.com/virtualization/technologies/vm/downloads/virtualbox-downloads.html" | grep -iF "latest release" | sed -e 's/^[ \t]*//' | cut -d" " -f6 | cut -d"." -f1-3)"
#virtualboxVersion="$(apt list --installed 2>/dev/null |grep "virtualbox-" | cut -d"/" -f1)"
#virtualboxVersionAvailable="$(apt-cache search VirtualBox | grep "virtualbox-" | tail -n1 | cut -d" " -f1)"
phpvirtualboxBranch="develop"
phpvirtualboxPath="/var/www/html/vbox"
phpvirtualboxVersion="$(cat $phpvirtualboxPath/CHANGELOG.txt | head -n2 | tail -n1 | sed -e 's/^[ \t]*//')"

# Cleanup trap
trap cleanup EXIT

printGood () {
    echo -e "\x1B[01;32m[+]\x1B[0m $1"
}

printError () {
    echo -e "\x1B[01;31m[-]\x1B[0m $1"
}

printStatus () {
    echo -e "\x1B[01;35m[*]\x1B[0m $1"
}

printQuestion () {
    echo -e "\x1B[01;33m[?]\x1B[0m $1"
}

testingScript(){
    set -x
    upgradePHPVirtualBox
    set +x
    stty sane
}

cleanup(){
    echo "" >> $logFile
    stty sane
    echo; exit $?
}

listAllVMs(){
    echo; howManyVMs=$(VBoxManage list vms | wc -l | awk '{ print $1 }')
    if [[ $howManyVMs == 0 ]]; then
        echo; printError "No VMs were found; are you running as the correct VirtualBox user?"
    else
        echo; printStatus "VMs currently registered with VirtualBox:"
        echo
        VBoxManage list vms
    fi
}

listRunningVMs(){
    echo; runningVMs=$(VBoxManage list runningvms | wc -l | awk '{ print $1 }')
    if [[ $runningVMs == 0 ]]; then
        echo; printError "No running VMs were found; are you running as the correct VirtualBox user?"
    else
        echo; printStatus "VMs currently running:"
        echo
        VBoxManage list runningvms
    fi
}

listAutostartVMs(){
    rm -f /tmp/autostart.vms
    echo; autostartVMs=$(VBoxManage list --long vms |grep "^Autostart Enabled:           enabled" | wc -l | awk '{ print $1 }')
    if [[ $autostartVMs == 0 ]]; then
        echo; printError "No autostart VMs were found; are you running as the correct VirtualBox user?"
    else
        echo; printStatus "VMs currently set to autostart:"
        echo
        for i in `VBoxManage list vms`; do
            vmName=`echo "$i" | cut -d"\"" -f 2`
            if [[ $(VBoxManage showvminfo "$vmName" |grep "^Autostart Enabled:           enabled") ]]; then echo $vmName && echo $vmName >> /tmp/autostart.vms; fi
        done
    fi
}

startVM(){
    echo; printQuestion "Please select a vm to START:\n"
    select i in `VBoxManage list vms`; do
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l | awk '{ print $1 }')
        if [[ $runningvm -ge "1" ]]; then
            printError "Error, that VM is already running."
        else
            echo; printStatus "Starting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi
        break
    done
}

shutdownVM(){
    # Try to shutdown gracefully
    echo; printStatus "Trying to gracefully shutdown:  $vmName"
    VBoxManage controlvm "$vmName" acpipowerbutton
    echo; printStatus "Watching for VM shutdown (after 30 seconds, VM will be hard shutdown)."
    count=0
    while [[ $count -lt 30 ]]; do
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l | awk '{ print $1 }')
        if [[ $runningvm == "0" ]]; then
            break
        else
            sleep 1
            ((count+=1))
        fi
    done
    runningvm=$(VBoxManage list runningvms | grep $i | wc -l | awk '{ print $1 }')
    if [[ $runningvm == "0" ]]; then
        printGood "VM gracefully powered off."
    else
        printError "VM did not power off gracefully, performing hard shutdown."
        VBoxManage controlvm "$vmName" poweroff
    fi
}


stopVM(){
    echo; printQuestion "Currently running VMs - please select a vm to STOP:\n"
    select i in `VBoxManage list runningvms`; do
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l | awk '{ print $1 }')
        if [[ $runningvm == "0" ]]; then
            printError "Error, that VM is already stopped."
        else
            shutdownVM
        fi
        break
    done
}

resetVM(){
    echo; printQuestion "Please select a vm to RESET:\n"
    select i in `VBoxManage list vms`; do
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l | awk '{ print $1 }')
        if [[ $runningvm == "0" ]]; then
            printError "Error, that VM is not running, trying to start up."
            VBoxManage startvm "$vmName" --type headless
        else
            echo; printStatus "Resetting:  $vmName"
            VBoxManage controlvm "$vmName" reset
        fi
        break
    done
}

checkVMStatus(){
    # Default vm running state is 'off'
    runningflag=0
    # Check if vm is running
    runningvm=$(VBoxManage list runningvms | grep $i | wc -l | awk '{ print $1 }')
    if [[ $runningvm -ge 1 ]]; then
        echo; printError "Error, you can NOT configure autostart on a running VM."
        printQuestion "Do you want to shutdown the VM in order to configure autostart? [y/N] "; read response
        response=${response,,}    # tolower
        if [[ $response =~ ^(yes|y)$ ]]; then
            shutdownVM
            # Since this function ran, we can assume the vm was running prior and we will set the running flag so the vm restarts
            export runningflag=1
        else
            echo; printError "User requested exit; autostart NOT configured on $vmName."
            break
        fi
    fi
}

configureVMAutostart(){
    echo; printError "WARNING:  This is completely rebuild your autostart database and"
    echo "    REMOVE all current autostart configurations."
    echo; printQuestion "Do you want to continue? (y/N)"; read reply
    if [[ $reply =~ ^[Yy]$ ]]; then
        # Check for vboxautostart-service file
        if [[ ! -f /etc/init.d/vboxautostart-service ]]; then
            cd /etc/init.d/
            sudo wget http://www.virtualbox.org/browser/vbox/trunk/src/VBox/Installer/linux/vboxautostart-service.sh?format=raw -O vboxautostart-service
            sudo chmod +x vboxautostart-service
            sudo update-rc.d vboxautostart-service defaults 24 24
        fi
        # Check for proper config in /etc/default/virtualbox
        sudo sed -i '/VBOXAUTOSTART_DB/d' $virtualboxConfig
        sudo sed -i '/VBOXAUTOSTART_CONFIG/d' $virtualboxConfig
        sudo sed -i '/SHUTDOWN_USER/d' $virtualboxConfig
        sudo sed -i '/SHUTDOWN/d' $virtualboxConfig
        echo "VBOXAUTOSTART_DB=$vboxAutostartDB" | sudo tee -a $virtualboxConfig > /dev/null 2>&1
        echo "VBOXAUTOSTART_CONFIG=$vboxAutostartConfig" | sudo tee -a $virtualboxConfig > /dev/null 2>&1
        echo "SHUTDOWN_USERS=all" | sudo tee -a $virtualboxConfig > /dev/null 2>&1
        echo "SHUTDOWN=savestate" | sudo tee -a $virtualboxConfig > /dev/null 2>&1
        # Check for autostart DB file
        sudo rm -rf $vboxAutostartDB > /dev/null 2>&1
        sudo mkdir $vboxAutostartDB > /dev/null 2>&1
        sudo chgrp vboxusers $vboxAutostartDB
        sudo chmod 1775 $vboxAutostartDB
        # Check for autostart config file
        sudo touch $vboxAutostartConfig
        sudo chown $vboxUser:$vboxUser $vboxAutostartConfig
        sudo chmod 644 $vboxAutostartConfig
        sed "s,%VBOXUSER%,$vboxUser,g" > $vboxAutostartConfig << 'EOF'
default_policy = deny
%VBOXUSER% = {
allow = true
}
EOF
        sudo usermod -aG vboxusers $vboxUser
        # Set the path to the autostart database directory
        VBoxManage setproperty autostartdbpath /etc/vbox
        # Check for .start and .stop files
        echo "1" | sudo tee /etc/vbox/redteam.start > /dev/null 2>&1
        echo "1" | sudo tee /etc/vbox/redteam.stop > /dev/null 2>&1
        sudo chown redteam /etc/vbox/redteam.st*
    fi
}

enableVMAutostart(){
    # Select system to autostart
    echo; printQuestion "Please select a vm on which to ENABLE autostart at system boot:\n"
    select i in `VBoxManage list vms`; do
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        checkVMStatus
        VBoxManage modifyvm "$vmName" --autostart-enabled on --autostop-type savestate
        echo; printGood "Autostart ENABLED on $vmName"
        # If machine was running prior to config, then restart
        if [[ $runningflag == 1 ]]; then
            echo; printStatus "Restarting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi
        break
        sudo service vboxautostart-service restart
    done
}

disableVMAutostart(){
    listAutostartVMs
    echo; printQuestion "Please select a vm on which to DISABLE autostart at system boot:\n"
    select i in $(cat /tmp/autostart.vms); do
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        checkVMStatus
        VBoxManage modifyvm "$vmName" --autostart-enabled off
        echo; printGood "Autostart DISABLED on $vmName"
        # If machine was running prior to config, then restart
        if [[ $runningflag == 1 ]]; then
            echo; printStatus "Restarting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi
        break
    done
}

upgradeExtensionPack(){
    version=$(vboxmanage -v)
    var1=$(echo $version | cut -d 'r' -f 1)
    var2=$(echo $version | cut -d 'r' -f 2)
    extensionfile="Oracle_VM_VirtualBox_Extension_Pack-$var1-$var2.vbox-extpack"
    echo; printStatus "Downloading entension pack:  $extensionfile"
    wget -c http://download.virtualbox.org/virtualbox/$var1/$extensionfile -O /tmp/$extensionfile
    # sudo VBoxManage extpack uninstall "Oracle VM VirtualBox Extension Pack"
    yes | sudo VBoxManage extpack install /tmp/$extensionfile --replace
}

upgradeVirtualBox(){
    # Check OS
    if [[ -z $os ]]; then
        echo; printError "Error:  This tool only upgrades VirtualBox on Debian-based systems."
        echo; break
    fi
    # Check for running vbox service/vboxdrv/vms
    if [[ $(ps aux | grep VBoxSVC | grep -v "grep" | echo $?) == 0 ]]; then
        if [[ -z $(service vboxdrv status | grep "not loaded") ]]; then
            runningvm=$(VBoxManage list runningvms | wc -l | awk '{ print $1 }')
            if [[ $runningvm -ge 1 ]]; then
                echo; printError "Error, you can NOT upgrade VirtualBox when you have running vms."
                echo "    Stop all running VMs and try again."
                exit 0
            fi
            echo; printStatus "Shutting down vboxdrv service."
            sudo service vboxdrv stop > /dev/null
        fi
        vboxsvcPID=$(ps aux | grep VBoxSVC | grep -v "grep" | awk '{ print $2 }')
        kill -9 $vboxsvcPID
    fi
    # Move out old dkms folder
    sudo mv /var/lib/dkms/vboxhost/$virtualboxVersionShort ~/var-lib-dkms-vboxhost-$virtualboxVersionShort.backup

    # Update packages
    echo; printStatus "Updating packages."
    sudo apt-get update; sudo apt-get -y upgrade
    sudo /sbin/vboxconfig
    # Setup vboxdrv
    sudo /sbin/rcvboxdrv setup
    upgradeExtensionPack
    echo; printGood "Upgrade complete; check output for any errors."
    echo "A backup of your dkms vbox folder was saved to ~/var-lib-dkms-vboxhost-$virtualboxVersionShort.backup"
    echo "If you did not see any dkms errors during the install, you may safely delete this backup folder."
}

restartVboxWebSvc(){
    echo; printStatus "Attempting to restart the VBox Web Service"
    sudo systemctl stop vboxweb-service; sleep 2
    sudo systemctl enable vboxweb-service; sleep 2
    sudo systemctl start vboxweb-service; sleep 2
    echo; printStatus "Checking if VBox Web Service is running"
    sudo systemctl status vboxweb-service
}

upgradePHPVirtualBox(){
    timeStamp="$(date +%Y%m%d)"
    echo; printStatus "Updating phpvirtualbox"
    cd $HOME
    if [[ ! `which zip` ]]; then
        printError "I need to download the program:  zip"
        sudo apt-get update; sudo apt-get -y install zip
    fi
    wget https://github.com/phpvirtualbox/phpvirtualbox/archive/$phpvirtualboxBranch.zip -O phpvirtualbox-$phpvirtualboxBranch.zip
    # wget https://sourceforge.net/projects/phpvirtualbox/files/latest/download -O phpvirtualbox-latest.zip
    # Compress previous backup
    if [[ -d ./phpvirtualbox.backup1 ]]; then
        sudo zip -r ./phpvirtualbox.backup2.zip ./phpvirtualbox.backup1
        if [[ -f ./phpvirtualbox.backup2.zip ]]; then
            sudo rm -rf ./phpvirtualbox.backup1
        else
            echo; printError "Errors on zip install; could not compress older phpvirtualbox folder into zip file."
            echo "Older backup folder moved to ./phpvirtualbox.backup2"
            echo; sudo mv ./phpvirtualbox.backup1 ./phpvirtualbox.backup2
        fi
    fi
    # Backup current install
    sudo mv $phpvirtualboxPath ./phpvirtualbox.backup1
    # Unzip latest version
    sudo unzip ./phpvirtualbox-$phpvirtualboxBranch.zip -d /var/www/html
    sudo mv /var/www/html/phpvirtualbox-$phpvirtualboxBranch $phpvirtualboxPath
    # Copy previous config file to new install
    sudo cp ./phpvirtualbox.backup1/config.php $phpvirtualboxPath/
    # Restart vbox web service
    restartVboxWebSvc
    echo; printGood "phpvirtualbox update completed."
}

installVirtualBox(){
    # Check internet connectivity
    checkInternet(){
        printStatus "Checking internet connectivity..."
        if [[ $internet == "1" || -z $internet ]]; then
            # Check internet connecivity
            WGET=`which wget`
            $WGET -q --tries=10 --timeout=5 --spider -U "Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; AS; rv:11.0) like Gecko" http://ipchicken.com
            if [[ $? -eq 0 ]]; then
                printGood "Internet connection confirmed."
                internet=1
            else
                echo; printError "No internet connectivity."
                internet=0
            fi
        fi
    }

    # Install VirtualBox
    checkInternet    
    if [[ $internet == 1 ]]; then
        # Install virtualbox and phpvirtualbox via phpvirtualbox install script
        wget https://raw.githubusercontent.com/phpvirtualbox/phpvirtualbox/develop/packaging/install-scripts/install.bash
        sudo bash $phpvirtualboxPath/packaging/install-scripts/install.bash -a --accept-extpack-license --install-extpack --install-dir=$phpvirtualboxPath --vbox-user=$vboxUser
        echo; printGood "RECOMMENDATIONS:"
        echo "-  Confirm the correct username and password are listed in /var/www/html/virtualbox/config.php"
        echo "-  Check your apache2 instance to ensure it is running and on which port (run 'sudo ss -ltpn | grep apache2')"
        exit 0

        # Original method to install virtualbox and phpvirtualbox
        # echo; wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
        # echo; wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -
        # echo; sudo add-apt-repository "deb [arch=amd64] http://download.virtualbox.org/virtualbox/debian $(lsb_release -cs) contrib"
        # echo; sudo apt update && echo; sudo apt-cache search VirtualBox | grep "virtualbox-"
        # printQuestion "What version of VirtualBox would you like to install? [i.e. \"6.1\"]"; read VERSION
        # echo; sudo apt -y install unzip apache2 php libapache2-mod-php php-soap php-xml php-json php-mysql virtualbox-$VERSION
        # # Install vbox extension pack
        # upgradeExtensionPack
        # # Enable php soap extension
        # phpVersion=$(php --version | head -n1 | cut -f2 -d' ' | cut -f1-2 -d'.')
        # sudo sed -i "s/;extension=soap/extension=soap/g" /etc/php/$phpVersion/apache2/php.ini
        # # Install phpvirtualbox
        # wget https://github.com/phpvirtualbox/phpvirtualbox/archive/$phpvirtualboxBranch.zip
        #     # wget https://github.com/phpvirtualbox/phpvirtualbox/archive/master.zip 
        # sudo unzip -d /var/www/html $phpvirtualboxBranch.zip && rm phpvirtualbox-$phpvirtualboxBranch.zip && sudo mv /var/www/html/phpvirtualbox-$phpvirtualboxBranch $phpvirtualboxPath
        # # Add user to vboxusers (enabling usb access, etc)
        # sudo usermod -a -G vboxusers $USER
        # # Identify default vbox user and host (in case vbox is running on another system)
        # echo "VBOXWEB_USER=$USER" | sudo tee /etc/default/virtualbox
        # echo "VBOXWEB_HOST=127.0.0.1" | sudo tee -a /etc/default/virtualbox
        # # Create default config file
        # sudo cp /var/www/html/vbox/config.php-example /var/www/html/vbox/config.php
        # sudo sed -i "s/var \$username.*/var \$username = $USER';/g" /var/www/html/vbox/config.php
        # printQuestion "What is the password for $USER (this will be used in phpvirtualbox's config.php)?"; read PASS
        # sudo sed -i "s/var \$password.*/var \$password = '$PASS';/g" /var/www/html/vbox/config.php
        # # Restart vbox web service
        # sudo systemctl restart apache2
        # restartVboxWebSvc
    else
        echo; printError "You are not connected to the internet; connect to the internet and try again. Exiting..."
        exit 1
    fi
}

removeVirtualBox(){
    sudo apt remove virtualbox virtualbox-*
}

# Loop to redisplay mhf
whattodo(){
    echo; printQuestion "What would you like to do next?"
    echo "1)List-All-VMs  2)List-Running-VMs  3)List-Autostart-VMs  4)Start-VM  5)Stop-VM  6)Reset-VM  7)Enable-VM-Autostart  8)Disable-VM-Autostart  9)Configure-VM-Autostart  10)Upgrade-VirtualBox  11)Upgrade-phpvirtualbox  12)Restart-VBox-Web-Service  13)Exit"
}

interactiveMode(){
    echo; printQuestion "What you would like to do:"
    echo
    select menu in "List-All-VMs" "List-Running-VMs" "List-Autostart-VMs" "Start-VM" "Stop-VM" "Reset-VM" "Enable-VM-Autostart" "Disable-VM-Autostart" "Configure-VM-Autostart" "Upgrade-VirtualBox" "Upgrade-phpvirtualbox" "Restart-VBox-Web-Service" "Exit"; do
        case $menu in
        List-All-VMs)
        listAllVMs
        whattodo
        ;;

        List-Running-VMs)
        listRunningVMs
        whattodo
        ;;

        List-Autostart-VMs)
        listAutostartVMs
        whattodo
        ;;

        Start-VM)
        startVM
        whattodo
        ;;

        Stop-VM)
        stopVM
        whattodo
        ;;

        Reset-VM)
        resetVM
        whattodo
        ;;

        Enable-VM-Autostart)
        enableVMAutostart
        whattodo
        ;;

        Disable-VM-Autostart)
        disableVMAutostart
        whattodo
        ;;

        Configure-VM-Autostart)
        configureVMAutostart
        whattodo
        ;;

        Upgrade-VirtualBox)
        upgradeVirtualBox
        whattodo
        ;;

        Upgrade-phpvirtualbox)
        upgradePHPVirtualBox
        whattodo
        ;;

        Restart-VBox-Web-Service)
        restartVboxWebSvc
        whattodo
        ;;

        Exit)
        echo; printStatus "User requested to exit."
        unset IFS
        echo; exit 1
        ;;
        esac
    done
}

printHelp(){
    echo "Usage: $vboxScript.sh [-h] [-i] [-u]"
    echo
}

#### MAIN PROGRAM ####

# Logging
exec &> >(tee "$logFile")

# Start
echo; echo "VirtualBox VM Control Script - Version $version"
printGood "Started:  $(date)"
printGood "Author:  spatiald"
if [[ ! -f $vboxManageExe ]]; then
    echo; printQuestion "It appears you do not have VirtualBox installed...do you want to install VirtualBox? [Y/n]"; read REPLY
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo; printStatus "We will NOT install VirtualBox, exiting."
        exit 1
    else 
        installVirtualBox
    fi
    echo
fi
printGood "Oracle VM VirtualBox Version Installed:  $virtualboxVersionShort"
if [[ "$virtualboxVersionShort" = "$virtualboxVersionAvailable" ]]; then virtualboxVersionAvailable="[The latest version is installed]"; fi
printGood "Oracle VM VirtualBox Version Available:  $virtualboxVersionAvailable"
printGood "phpVirtualBox Version Installed:  $phpvirtualboxVersion"
printGood "Running as user:  $(whoami)"
printGood "Logging to file:  $logFile"

# Non-interactive menu
if [[ $1 == "--help" ]]; then
    echo; printHelp
elif [[ $1 == "" ]]; then
    interactiveMode
else
    IAM=${0##*/} # Short basename
    while getopts ":hilrtu" opt
    do sc=0 #no option or 1 option arguments
        case $opt in
        (h) # Print help/usage statement
            echo; printHelp
            echo "Examples:"
            echo "./$vboxScript.sh -h"
            echo "Displays this help menu."
            echo; echo "./$vboxScript.sh -i"
            echo "Interactive mode."
            echo; echo "./$vboxScript.sh -u"
            echo "Update $vboxScript.sh with latest version from Github."
            echo
            ;;
        (i) # Fully interactive mode
            interactiveMode >&2
            ;;
        (r) # Remove VirtualBox
            printQuestion "Are you certain that you want to remove VirtualBox (it will note delete the VMs)? [y/N]"; read REPLY
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                removeVirtualBox >&2
                printGood "VirtualBox removed.  Your VMs are most likely located in the directory \"$HOME/Virtualbox VMs\"."
            else 
                echo; printStatus "We will NOT remove VirtualBox."
                exit 1
            fi
            ;;
        (t) # Testing script
            testingScript >&2
            ;;
        (u) # UPDATE - Update $vboxScript to the latest release build.
            cd $HOME
            wget https://github.com/spatiald/vbox-control/raw/master/vbox-control.sh -O $vboxScript.sh
            chmod +x $vboxScript.sh
            if [[ -f $vboxScript.sh ]]; then echo; printGood "$vboxScript.sh downloaded to $HOME/$vboxScript.sh"; fi
            ;;
        (\?) #Invalid options
            echo "$IAM: Invalid option: -$OPTARG"
            printHelp
            exit 1
            ;;
        (:) #Missing arguments
            echo "$IAM: Option -$OPTARG argument(s) missing."
            printHelp
            exit 1
            ;;
        esac
        if [[ $OPTIND != 1 ]]; then #This test fails only if multiple options are stacked after a single "-"
            shift $((OPTIND - 1 + sc))
            OPTIND=1
        fi
    done
fi

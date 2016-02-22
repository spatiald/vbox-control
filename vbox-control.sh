#!/bin/bash
# Ignore spaces as line breaks in for loop
version="2"
IFS=$(echo -en "\n\b")
vboxmanageexe=$(which VBoxManage)
vboxUser="redteam"
virtualboxConfig="/etc/default/virtualbox"
vboxAutostartDB="/etc/vbox"
vboxAutostartConfig="/etc/vbox/autostart.cfg"

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

listAllVMs(){
    echo; howManyVMs=$(VBoxManage list vms | wc -l)
    if [[ $howManyVMs == 0 ]]; then
        echo; printError "No VMs were found; are you running as the correct Virtualbox user?"
    else
        echo; printStatus "VMs currently registered with Virtualbox:"
        echo
        VBoxManage list vms
    fi
}

listRunningVMs(){
    echo; howManyVMs=$(VBoxManage list runningvms | wc -l)
    if [[ $howManyVMs == 0 ]]; then
        echo; printError "No running VMs were found; are you running as the correct Virtualbox user?"
    else
        echo; printStatus "VMs currently running:"
        echo
        VBoxManage list runningvms
    fi
}

startVM(){
    echo; printQuestion "Please select a vm to START:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
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
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
        if [[ $runningvm == "0" ]]; then
            break
        else
            sleep 1
            ((count+=1))
        fi
    done
    runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
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
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
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
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
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
    runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
    if [[ $runningvm -ge 1 ]]; then 
        echo; printError "Error, you can NOT configure autostart on a running VM."
        printQuestion "Do you want to shutdown the VM in order to configure autostart? [y/N] "; read response
        response=${response,,}    # tolower
        if [[ $response =~ ^(yes|y)$ ]]; then
            shutdownVM
            export runningflag=0
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
        echo "VBOXAUTOSTART_DB=$vboxAutostartDB" | sudo tee -a $virtualboxConfig >/dev/null
        echo "VBOXAUTOSTART_CONFIG=$vboxAutostartConfig" | sudo tee -a $virtualboxConfig >/dev/null
        # Check for autostart DB file
        sudo rm -rf $vboxAutostartDB 2>/dev/null
        sudo mkdir $vboxAutostartDB 2>/dev/null
        sudo chgrp vboxusers $vboxAutostartDB
        sudo chmod 1775 $vboxAutostartDB
        # Check for autostart config file
        sudo rm -rf $vboxAutostartConfig 2>/dev/null
        sudo touch $vboxAutostartConfig
        sudo chown $vboxUser:$vboxUser $vboxAutostartConfig
        sudo chmod 644 $vboxAutostartConfig
        sed "s,%VBOXUSER%,$vboxUser,g" > $vboxAutostartConfig << 'EOF'
default_policy = allow
%VBOXUSER% = {
allow=true
}
EOF
        # Set the path to the autostart database directory
        VBoxManage setproperty autostartdbpath /etc/vbox
    fi
}

enableVMAutostart(){
    # Select system to autostart
    echo; printQuestion "Please select a vm on which to ENABLE autostart at system boot:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        checkVMStatus
        VBoxManage modifyvm "$vmName" --autostart-enabled on
        echo; printGood "Autostart ENABLED on $vmName"
        if [[ $runningflag == 0 ]]; then
            echo; printStatus "Restarting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi
        break
    done
    # Restart the vboxauto service
#    service vboxautostart-service stop
#    service vboxautostart-service start
}

disableVMAutostart(){
    echo; printQuestion "Please select a vm on which to DISABLE autostart at system boot:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then printError "Exiting, you did not choose an existing VM."; fi
        checkVMStatus
        VBoxManage modifyvm "$vmName" --autostart-enabled off
        echo; printGood "Autostart DISABLED on $vmName"
        if [[ $runningflag == 0 ]]; then
            echo; printStatus "Restarting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi
        break
    done
    # Restart the vboxauto service
#    service vboxautostart-service stop
#    service vboxautostart-service start
}

# Loop to redisplay mhf
whattodo(){
    echo; printQuestion "What would you like to do next?"
    echo "1)List-All-VMs  2)List-Running-VMs  3)Start-VM  4)Stop-VM  5)Reset-VM  6)Enable-VM-Autostart  7)Disable-VM-Autostart  8) Configure-VM-Autostart  9)Exit"
}

## MAIN MENU
echo; echo "Virtualbox VM Control Script - Version $version"
echo "-- Author spatialD"

echo; printStatus "Running as user:  $(whoami)"

if [[ ! -f $vboxmanageexe ]]; then
    echo; printStatus "Checking for VBoxManage (normally in /usr/bin/VBoxManage)."
    printError "It appears you do not have Virtualbox installed...no reason to run, exiting."
    echo; exit 1
fi

echo; printQuestion "What you would like to do:" | tee -a $RACHELLOG
echo
select menu in "List-All-VMs" "List-Running-VMs" "Start-VM" "Stop-VM" "Reset-VM" "Enable-VM-Autostart" "Disable-VM-Autostart" "Configure-VM-Autostart" "Exit"; do
        case $menu in
        List-All-VMs)
        listAllVMs
        whattodo
        ;;

        List-Running-VMs)
        listRunningVMs
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

        Exit)
        echo; printStatus "User requested to exit."
        unset IFS
        echo; exit 1
        ;;
        esac
done
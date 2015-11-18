#!/bin/bash
# Ignore spaces as line breaks in for loop
version="2"
IFS=$(echo -en "\n\b")
vboxmanageexe=$(which VBoxManage)

function print_good () {
    echo -e "\x1B[01;32m[+]\x1B[0m $1"
}

function print_error () {
    echo -e "\x1B[01;31m[-]\x1B[0m $1"
}

function print_status () {
    echo -e "\x1B[01;35m[*]\x1B[0m $1"
}

function print_question () {
    echo -e "\x1B[01;33m[?]\x1B[0m $1"
}

function list_vms (){
    howManyVMs=$(VBoxManage list vms | wc -l)
    if [[ $howManyVMs == 0 ]]; then
        echo; print_error "No VMs were found; are you running as the correct Virtualbox user?"
    else
        echo; print_status "VMs currently registered with Virtualbox:"
        echo
        VBoxManage list vms
    fi
}

function start_vm (){
    print_question "Please select a vm to START:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then print_error "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
        if [[ $runningvm -ge "1" ]]; then 
            print_error "Error, that VM is already running."
        else
            echo; print_status "Starting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi
        break
    done
}

function stop_vm (){
    print_question "Please select a vm to STOP:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then print_error "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
        if [[ $runningvm == "0" ]]; then 
            print_error "Error, that VM is already stopped."
        else
            echo; print_status "Trying to gracefully shutdown:  $vmName"
            VBoxManage controlvm "$vmName" acpipowerbutton
            echo; print_status "Waiting 30 seconds for VM to shutdown..."
            sleep 30
            echo; print_status "Checking VM status."
            runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
            if [[ $runningvm == "0" ]]; then
                print_good "VM gracefully powered off."
            else
                print_error "VM did not power off graefully, performing hard shutdown."
                VBoxManage controlvm "$vmName" poweroff
            fi
        fi
        break
    done
}

function reset_vm (){
    print_question "Please select a vm to RESET:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then print_error "Exiting, you did not choose an existing VM."; fi
        runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
        if [[ $runningvm == "0" ]]; then 
            print_error "Error, that VM is not running, trying to start up."
            VBoxManage startvm "$vmName" --type headless
        else
            echo; print_status "Resetting:  $vmName"
            VBoxManage controlvm "$vmName" reset
        fi
        break
    done
}

function check_vm_status (){
    runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
    if [[ $runningvm -ge "1" ]]; then 
        export runningflag=1
        echo; print_error "Error, you can NOT configure autostart on a running VM."
        read -r -p "Do you want to shutdown the VM in order to configure autostart? [y/N] " response
        response=${response,,}    # tolower
        if [[ $response =~ ^(yes|y)$ ]]; then
            echo; print_status "Trying to gracefully shutdown:  $vmName"
            VBoxManage controlvm "$vmName" acpipowerbutton
            echo; print_status "Waiting 30 seconds for VM to shutdown..."
            sleep 30
            echo; print_status "Checking VM status."
            runningvm=$(VBoxManage list runningvms | grep $i | wc -l)
            if [[ $runningvm == "0" ]]; then
                print_good "VM gracefully powered off."
            else
                print_error "VM did not power off graefully, performing hard shutdown."
                VBoxManage controlvm "$vmName" poweroff
            fi
        else
            echo; print_error "Autostart NOT configured on $vmName."
            break
        fi
    fi
}

function enable_vm_autostart (){
    echo; print_question "Please select a vm on which to ENABLE autostart at system boot:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then print_error "Exiting, you did not choose an existing VM."; fi
        check_vm_status
        VBoxManage modifyvm "$vmName" --autostart-enabled on
        echo; print_good "Autostart ENABLED on $vmName"
        if [[ $runningflag == "1" ]]; then
            echo; print_status "Restarting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi            
        break
    done
}

function disable_vm_autostart (){
    echo; print_question "Please select a vm on which to DISABLE autostart at system boot:\n"
    select i in `VBoxManage list vms`; do 
        vmName=`echo "$i" | cut -d"\"" -f 2`
        if [[ $i == "" ]]; then print_error "Exiting, you did not choose an existing VM."; fi
        check_vm_status
        VBoxManage modifyvm "$vmName" --autostart-enabled off
        echo; print_good "Autostart DISABLED on $vmName"
        if [[ $runningflag == "1" ]]; then
            echo; print_status "Restarting:  $vmName"
            VBoxManage startvm "$vmName" --type headless
        fi            
        break
    done
}

# Loop function to redisplay mhf
function whattodo {
    echo; print_question "What would you like to do next?"
    echo "1)List-VMs  2)Start-VM  3)Stop-VM  4)Reset-VM  5)Enable-VM-Autostart  6)Disable-VM-Autostart  7)Exit"
}

## MAIN MENU
echo; echo "Virtualbox VM Control Script - Version $version"
echo "-- Author spatialD"

echo; print_status "Running as user:  $(whoami)"

if [[ ! -f $vboxmanageexe ]]; then
    echo; print_status "Checking for VBoxManage (normally in /usr/bin/VBoxManage)."
    print_error "It appears you do not have Virtualbox installed...no reason to run, exiting."
    echo; exit 1
fi

echo; print_question "What you would like to do:" | tee -a $RACHELLOG
echo
select menu in "List-VMs" "Start-VM" "Stop-VM" "Reset-VM" "Enable-VM-Autostart" "Disable-VM-Autostart" "Exit"; do
        case $menu in
        List-VMs)
        list_vms
        whattodo
        ;;

        Start-VM)
        start_vm
        whattodo
        ;;

        Stop-VM)
        stop_vm
        whattodo
        ;;

        Reset-VM)
        reset_vm
        whattodo
        ;;

        Enable-VM-Autostart)
        enable_vm_autostart
        whattodo
        ;;

        Disable-VM-Autostart)
        disable_vm_autostart
        whattodo
        ;;

        Exit)
        echo; print_status "User requested to exit."
        unset IFS
        echo; exit 1
        ;;
        esac
done

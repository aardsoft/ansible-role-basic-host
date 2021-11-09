#!/bin/sh
# aws-tool.sh
# (c) 2021 Bernd Wachter <bwachter-github@aardsoft.fi>

if ((BASH_VERSINFO[0] < 4)); then
    echo "Bash version >= 4 required"
    exit 1
fi

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}

declare -A _opts=()

if [ -f $XDG_CONFIG_HOME/aardsoft/aws-tool ]; then
    . $XDG_CONFIG_HOME/aardsoft/aws-tool
fi

_OPTS=`getopt -o i:k:hp -l base64-password,instance,instances,instance-ids,ip,key,rdp,help \
             -n 'aws-tool' -- "$@"`
if [ $? -ne 0 ]; then exit 1; fi
eval set -- "$_OPTS"

red(){
    echo -e "\e[31m$1\e[0m"
}

red_bold(){
    echo -e "\e[31m\e[1m$1\e[0m"
}

green(){
    echo -e "\e[32m$1\e[0m"
}

green_bold(){
    echo -e "\e[32m\e[1m$1\e[0m"
}

yellow(){
    echo -e "\e[33m$1\e[0m"
}

error(){
    red_bold "$1"
    exit 1
}

bug(){
    red_bold "[bug] $1"
    exit 1
}

aws_help(){
cat <<-EOF
Basic usage

-i|--instance
   --instances
-k|--key        the private key for decryption. May be pkcs11 to use a HSM
-h|--help
-p
   --rdp
   --ip


Options mostly useful for testing:

--base64-password  return the encrypted password as base64
--instance-ids     returns a list of instance IDs

Configuration options

This script reads configuration from $XDG_CONFIG_HOME/aardsoft/aws-tool
The configuration file contains an associative bash array, with valid options
listed below. Command line arguments override options from the configuration
file, though not all options may have arguments. The following example sets
pkcs11 as default key provider for crypto operations:

_opts=(
    ['key']="pkcs11"
)

Other keys are:

instance  a default instance ID
EOF
}

aws_get_password(){
    if [ -n "$1" ]; then
        _instance=$1
        shift
    else
        _instance=${_opts['instance']}
    fi

    if [ -z "$_instance" ]; then
        error "instance ID required"
    fi

    _r=`aws ec2 get-password-data --instance-id $_instance --query PasswordData --output text`

    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo $_r|sed 's/\s*//g'
}

aws_get_instance_ids(){
    aws ec2 describe-instances --filters Name=instance-state-name,Values=running --output text --query  "Reservations[*].Instances[*].[InstanceId]"
}

aws_list_instances(){
    aws ec2 describe-instances \
        --filters Name=instance-state-name,Values=running \
        --output table \
        --query 'Reservations[*].Instances[*].{Instance:InstanceId,AZ:Placement.AvailabilityZone,Name:Tags[?Key==`Name`]|[0].Value,IP:PrivateIpAddress,CPU:CpuOptions.CoreCount,Type:InstanceType}'
}

aws_password(){
    if [ -z "${_opts['key']}" ]; then
        error "No key specified"
    fi

    _key=`aws_get_password`
    if [ "${_opts['key']}" = "pkcs11" ]; then
        _tmp_in=`mktemp /tmp/aws_key.XXXXXX`
        _tmp_out=`mktemp /tmp/aws_key.XXXXXX`
        echo $_key|base64 -d > $_tmp_in
        aws_decode_password_pkcs11 $_tmp_in $_tmp_out
        rm -f $_tmp_in $_tmp_out
    else
        aws_decode_password_keyfile $_key ${_opts['key']}
    fi
}

aws_decode_password_pkcs11(){
    _in=$1
    shift
    _out=$1
    shift

    pkcs11-tool --decrypt -v -l --input-file $_in --output-file $_out -m RSA-PKCS
    _password=`cat $_out`
    rm -f $_out
    echo $_password
}

aws_decode_password_keyfile(){
    _key_data=$1
    shift
    _key=$1
    shift

    _password=`echo $_key_data|base64 -d|openssl rsautl -decrypt -inkey "$_key" `
    echo $_password
}

while true; do
    case "$1" in
        --base64-password)
            _func=get_password
            shift
            ;;
        -i|--instance)
            shift
            _opts['instance']=$1
            shift
            ;;
        --instance-ids)
            shift
            _func=get_instance_ids
            ;;
        --instances)
            shift
            _func=list_instances
            ;;
        -h|--help)
            _func=help
            shift
            ;;
        -k|--key)
            shift
            _opts['key']=$1
            shift
            ;;
        -p)
            shift
            _func=password
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unhandled option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$_func" ]; then
    echo "No idea what to do"
    exit 1
fi

_func=aws_$_func

"$_func" || error "Error calling $_func"

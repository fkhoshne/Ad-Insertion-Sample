#!/bin/bash -e

DIR=$(dirname $(readlink -f "$0"))
EXT=*.yaml

# Set Bash color
ECHO_PREFIX_INFO="\033[1;32;40mINFO...\033[0;0m"
ECHO_PREFIX_ERROR="\033[1;31;40mError...\033[0;0m"

# Try command  for test command result.
function try_command {
    "$@"
    status=$?
    if [ $status -ne 0 ]; then
        echo -e $ECHO_PREFIX_ERROR "ERROR with \"$@\", Return status $status."
        exit $status
    fi
    return $status
}

# This script must be run as root
if [[ $EUID -ne 0 ]]; then
    echo -e $ECHO_PREFIX_ERROR "This script must be run as root!" 1>&2
    exit 1
fi

try_command hash kubectl > /dev/null

for i in $(find "$DIR" -name "*deployment.yaml" -prune -o -type f -name "*.yaml" -print); do
    len=$(echo $DIR | wc -m)
    i1=$(echo ${i:${len}} | sed 's/-service.yaml//')
    for j in $(kubectl get svc | awk '{print $1}' | sed -n '2, $p' | grep -v 'kubernetes'); do
        if [ "$i1" == "$j" ]; then
	    kubectl delete -f "$i"
	fi
    done
done

for i in $(find "$DIR" -name "*deployment.yaml"); do
    len=$(echo $DIR | wc -m)
    i1=$(echo ${i:${len}} | sed 's/-deployment.yaml//')

    for j in $(kubectl get pod | awk '{print $1}' | sed -n '2, $p' | sed 's/service-.*$//' | sort | uniq); do
        #j1=$(echo $j | sed 's/service-.*$//')service
        j1=${j}service
        if [ ${i1} == ${j1} ]; then
            kubectl delete -f "${i}"
        fi
    done
done


if [ -f "$DIR/ovc-self-certificates.yaml" ]; then
    kubectl delete -f "$DIR/ovc-self-certificates.yaml"
fi


try_command "$DIR/update_yaml.py" "$DIR"

try_command "$DIR/self-sign.sh"


# Generate Secrets
try_command kubectl create secret generic ssl-key-secret --from-file=self.key="/home/self.key" --from-file=self.crt="/home/self.crt" --from-file=dhparam.pem="/home/dhparam.pem" --dry-run -o yaml > "$DIR/ovc-self-certificates.yaml"

try_command kubectl apply -f "$DIR/ovc-self-certificates.yaml"


for i in $(find "$DIR" -name "*service.yaml"); do
    kubectl apply -f "$i"
done

for i in $(find "$DIR" -name "*deployment.yaml"); do
    kubectl apply -f "$i"
done

sleep 2s

for i in $(find "$DIR" -name "*deployment.yaml"); do
    len=$(echo $DIR | wc -m)
    i1=$(echo ${i:${len}} | sed 's/-deployment.yaml//')

    while true; do
        if (kubectl get pod | awk '{print $1,$3}' | grep -q "${i1}.*Running"); then
            break
        else
            sleep 2s
        fi
    done
done

sleep 2s


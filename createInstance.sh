#!/bin/bash

# Necesitamos agregar las siguientes labels a las instancias:
# - migrate:true
# - newname=<nombre-instancia>
# - ip1 (usar - en lugar de .)
# - ip2 (usar - en lugar de .)
# - instance-group

###### Editar los valores siguientes ##########
SUBNET1=test-subnet
SUBNET2=admin-central
SCRIPT=gs://marioarz-test/startup-script-1.sh
SVCACCOUNT=instance-svc-account@main-testing.iam.gserviceaccount.com
GROUP=web-group
TAG=migrate
#####################################################################

help () {
    echo "Uso: "
    echo "$0 -t|--tag <Nombre-Tag> [-c|-r]"
    echo ""
    echo "    -t : Tag que se buscara para migrar. Valor debe ser true"
    echo "    -c : Crea la instancia adicional al snapshot"
    echo "    -g : Nombre del instance-group para agregar instancia"
    exit 1
}

if [ $# -le 1 ]; then
    help
    exit 1
fi

for i in "$@"
do
case $i in
    -c|--create)
    CREATE="true"
    shift # past argument
    ;;
    -g|--group)
    GROUP="$2"
    shift # past argument
    shift # past value
    ;;

esac
done

for INSTANCES in $(gcloud compute instances list --format="csv[no-heading,separator='|'](name, disks[0].source, zone, labels.newname, labels.ip1, labels.ip2, machineType)" --filter="labels.$TAG=true")
do
    IFS="|" read NAME DISK ZONE NEW_NAME IP1 IP2 TYPE <<<"${INSTANCES}"
    echo -e "Name: ${NAME}" 
    echo -e "Disk: ${DISK}"
    echo -e "Zone: ${ZONE}"
    echo -e "NewName: ${NEW_NAME}"
    echo -e "Subnet1: ${SUBNET1}"
    echo -e "Subnet1: ${SUBNET2}"
    echo -e "IP1: ${IP1}"
    echo -e "IP2: ${IP2}"
    echo -e "TYPE: ${TYPE}"
    echo "----------"
    echo "Apagando instancia: ${NAME}"
    gcloud compute instances stop ${NAME} --zone ${ZONE}
    IMGNAME=${NAME}-image-`date "+%m%d-%H%M"`
    echo "Instancia apagada. Iniciando creacion de imagen: ${IMGNAME}"
    gcloud compute images create ${IMGNAME} --format="[no-heading](name)" --source-disk=${DISK} 
    echo "Imagen creada"

    ## Si recibimos -c crearemos instancia(s) nueva(s)
    if [ "$CREATE" == "true" ] 
    then
    
     ## Consultar los discos en la instancia - desacoplarlos
     D=0 
     DISKS=$(gcloud compute instances list --format="value(disks.source)" --filter="labels.$TAG=true" | sed 's/;/ /g') 
     for DISK in $DISKS
        do
            if [ "$D" -gt 0 ]; then
                echo "Desacoplando disco: ${DISK}"
                gcloud compute instances detach-disk ${NAME} --disk ${DISK} --zone ${ZONE}
                gcloud compute disks add-labels ${DISK} --labels=instance=${NAME}
                gcloud compute disks add-labels ${DISK} --labels=number=$D
            fi 
            D=$((D+1))
        done

     #Labels no permiten puntos
     IP1=$(echo $IP1 | sed 's/-/./g')
     IP2=$(echo $IP2 | sed 's/-/./g')

     echo "Creando instancia: ${NEW_NAME}"
     CMD="gcloud compute instances create ${NEW_NAME}  \
        --machine-type=${TYPE} --image=${IMGNAME} --zone ${ZONE} \
        --network-interface=subnet=${SUBNET1},no-address,private-network-ip=${IP1} \
        --network-interface=subnet=${SUBNET2},no-address,private-network-ip=${IP2} \
        --metadata=startup-script-url=${SCRIPT} \
        --service-account=${SVCACCOUNT} " 
     
     D=0 
     for DISK in $DISKS
        do
            if [ "$D" -gt 0 ]; then
                DNAME=$(echo $DISK | sed 's/\// /g' |  awk '{print $10}')
                echo "Acoplando disco: ${DISK}"
                CMD+=" --disk=name=${DNAME} "
            fi 
            D=$((D+1))
        done
    fi  

    #echo $CMD
    eval $CMD

    # Agregando etiqueta
    # instance-group : group-1
    if [ ! -z ${GROUP+x} ]; then
        echo "GROUP: $GROUP"
        gcloud compute instances add-labels ${NEW_NAME} --zone ${ZONE} --labels=instance-group=${GROUP}-${ZONE}
    fi

    gcloud compute instances remove-labels ${NAME} --zone ${ZONE} --labels=$TAG
    gcloud compute instances add-labels ${NEW_NAME} --zone ${ZONE} --labels=copy-of=${NAME}
    gcloud compute instances add-labels ${NAME} --zone ${ZONE} --labels=migrated=completed

done
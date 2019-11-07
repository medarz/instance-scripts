#!/bin/bash

# Necesitamos agregar las siguientes labels a las instancias:
# - migrate:true
# - newname=<nombre-instancia>
# - ip1 (usar - en lugar de .)
# - ip2 (usar - en lugar de .)
# - [instance-group]
# - [newzone - zona a la que se moveria la instancia]

###### Editar los valores siguientes ##########
SUBNET1=test-subnet
SUBNET2=admin-central
SVCACCOUNT=instance-svc-account@main-testing.iam.gserviceaccount.com
GROUP=web-group
TAG=migrate
#####################################################################

help () {
    echo "Uso: "
    echo "$0  [-c | -n | -s]"
    echo ""
    echo "    -c : Crea la instancia adicional al snapshot"
    echo "    -n : Network tags separados por coma"
    echo "    -s : Ubicacion de GSC de Startup Script"
    echo ""
    exit 1
}

for i in "$@"
do
case $i in
    -c|--create)
    CREATE="true"
    shift # past arguments
    ;;
    -n|--net-tag)
    NET_TAG="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--script)
    SCRIPT=$2
    shift # past arguments
    shift # past value
    ;;
esac
done

echo "Buscando instancias con Etiqueta: $TAG"

for INSTANCES in $(gcloud compute instances list --format="csv[no-heading,separator='|'](name, disks[0].source, zone, labels.newname, labels.ip1, labels.ip2, labels.newzone)" --filter="labels.$TAG=true")
do
    IFS="|" read NAME DISK ZONE NEW_NAME IP1 IP2 NEW_ZONE <<<"${INSTANCES}"
    echo -e "Name: ${NAME}" 
    echo -e "Disk: ${DISK}"
    echo -e "Zone: ${ZONE}"
    echo -e "NewName: ${NEW_NAME}"
    echo -e "Subnet1: ${SUBNET1}"
    echo -e "Subnet1: ${SUBNET2}"
    echo -e "IP1: ${IP1}"
    echo -e "IP2: ${IP2}"
    echo -e "NEW_ZONE: ${NEW_ZONE}"
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
        --service-account=${SVCACCOUNT} " 
        
    # Startup Script
    if [ ! -z ${SCRIPT+x} ]; then
        echo "Startup Script: $SCRIPT"
        CMD+=" --metadata=startup-script-url=${SCRIPT} "
    fi

    # Network tags
    if [ ! -z ${NET_TAG+x} ]; then
        echo "Network Tags: $NET_TAG"
        CMD+=" --tags=${NET_TAG} "
    fi

    # Definir el tipo de instancia
    MTYPE=$(gcloud compute instances describe ${NAME} --format="csv[no-heading](machineType)" --zone ${ZONE} | awk '{split($0,a,"/"); print a[11]}')
    echo "Tipo de instancia: $MTYPE"
    if [[ "$MTYPE" =~ ^custom* ]]; then
        echo "Instancia Custom"
        CPU=$(echo $MTYPE | awk '{split($0,g,"-"); print g[2]}')
        (( GB= $(echo $MTYPE | awk '{split($0,g,"-"); print g[3]}')/1024 ))
        CMD+=" --custom-vm-type=n1 --custom-cpu=${CPU} --custom-memory=${GB}GB "
        #
    else
        echo "Standard type"
        CMD+=" --machine-type=${MTYPE} " 
    fi

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

    retVal=$?
    if [ $retVal -ne 0 ]; then
        echo "Error creando la instancia."
        echo "Borrando imagen"
        gcloud compute images delete ${IMGNAME} 
        exit $retVal
    fi
    
    # Agregando etiqueta
    # instance-group : 
    if [ ! -z ${GROUP+x} ]; then
        echo "Instance Group: $GROUP"
        gcloud compute instances add-labels ${NEW_NAME} --zone ${ZONE} --labels=instance-group=${GROUP}-${ZONE}
    fi

    gcloud compute instances remove-labels ${NAME} --zone ${ZONE} --labels=${TAG}
    gcloud compute instances add-labels ${NEW_NAME} --zone ${ZONE} --labels=copy-of=${NAME}
    gcloud compute instances add-labels ${NAME} --zone ${ZONE} --labels=${TAG}=completed

    # Moviendo la instancia de zona
    
    if [ ! -z ${NEW_ZONE} ]; then
        echo "Moviendo instancia a zona: ${NEW_ZONE}"
        gcloud compute instances move ${NEW_NAME} \
            --zone ${ZONE} --destination-zone ${NEW_ZONE}

        if [ ! -z ${GROUP+x} ]; then
            gcloud compute instances add-labels ${NEW_NAME} --zone ${NEW_ZONE} --labels=instance-group=${GROUP}-${NEW_ZONE}
        fi
        
    fi
    echo "Finalizado."

done

exit 0
#!/bin/bash

# Necesitamos agregar las siguientes labels a las instancias:
# - instance-group:<nombre>

###### Editar los valores siguientes ##########

#####################################################################

help () {
    echo "Uso: "
    echo "$0 -g|--group <Nombre-Instance-Group> -z|--zone <Zona> [-c|--create]"
    echo ""
    echo "    -g : Nombre del grupo que se buscara para agrupar instancias."
    echo "         Debe ser puesto a traves de una etiqueta (label)"
    echo "                instance-group:mi-grupo-1"
    echo "    -z : Zona donde se creara el Instance Group"
    echo "    -c : Crear Instance Group. De lo contrario solo asociara instancias"
    echo ""
    exit 1
}

if [ $# -lt 1 ]; then
    help
    exit 1
fi

for i in "$@"
do
    case $i in
        -g|--group)
        GROUP="$2"
        shift # past argument
        shift # past value
        ;;
        -z|--zone)
        ZONE="$2"
        shift # past argument
        shift # past value
        ;;
        -c|--create)
        CREATE="true"
        shift # past argument
        ;;
    esac
done

# Guardaremos aqui las instancias de la zona
IGROUP=""

for INSTANCES in $(gcloud compute instances list --format="csv[no-heading](name, zone)" --filter="labels.instance-group=$GROUP-$ZONE")
do
    IFS="," read NAME IZONE <<<"${INSTANCES}"
    echo -e "Name: ${NAME}" 
    echo -e "Zone: ${IZONE}"
    echo "----------"
    # Si son de la misma zona a la solicitada, las agregamos
    if [ "${ZONE}" == "${IZONE}" ] 
    then
        IGROUP+="${NAME},"
    fi
    
done

## Si recibimos -c crearemos instancia(s) nueva(s)
if (( ${#IGROUP} > 0 ))
then
    if [ "$CREATE" == "true" ] 
    then
        echo "Creando Grupo:"
        CMD1="gcloud compute instance-groups unmanaged create $GROUP-$ZONE --zone $ZONE"
        echo $CMD1
        eval $CMD1
    fi

    CMD2="gcloud compute instance-groups unmanaged add-instances $GROUP-$ZONE --instances=${IGROUP::-1} --zone $ZONE"
    echo $CMD2
    eval $CMD2
else
    echo "No hay instancias en la zona: $ZONE"
fi
#!/bin/bash

# ==============================
# Configuración de IP Estática
# Ubuntu Server - Netplan
# Interfaz: ens18
# ==============================

# Verificar que se ejecute como root
if [ "$EUID" -ne 0 ]; then
    echo "Ejecute este script como root o con sudo."
    exit 1
fi

# Variables (Modificar únicamente la IP si es necesario)
INTERFAZ="ens18"
IP="10.16.43.150"
PREFIJO="26"
GATEWAY="10.16.43.129"
DNS1="8.8.8.8"
DNS2="1.1.1.1"
ARCHIVO="/etc/netplan/50-cloud-init.yaml"

echo "Configurando IP estática..."

# Crear respaldo
cp $ARCHIVO ${ARCHIVO}.bak

# Generar configuración
cat > $ARCHIVO << EOF
network:
  version: 2
  ethernets:
    $INTERFAZ:
      dhcp4: false
      addresses:
        - $IP/$PREFIJO
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $DNS1
          - $DNS2
EOF

# Aplicar configuración
netplan generate
netplan apply

echo ""
echo "======================================="
echo "Configuración aplicada correctamente."
echo "======================================="
echo "Interfaz : $INTERFAZ"
echo "IP       : $IP/$PREFIJO"
echo "Gateway  : $GATEWAY"
echo "DNS      : $DNS1, $DNS2"
echo ""

ip addr show $INTERFAZ

# ==============================
# Configurar tarea programada (Crontab)
# ==============================
# Agregamos una entrada en /etc/cron.d/ para que este script 
# se ejecute al reiniciar el servidor.
echo "Configurando crontab para persistir la IP tras reiniciar..."
SCRIPT_PATH=$(realpath "$0")
CRON_FILE="/etc/cron.d/static_ip_on_reboot"

cat > $CRON_FILE << EOF
# Ejecutar configuración de IP estática al reiniciar
@reboot root /bin/bash $SCRIPT_PATH > /var/log/static_ip_reboot.log 2>&1
EOF
chmod 644 $CRON_FILE

echo "Crontab creado en $CRON_FILE"
echo "El servidor aplicará esta IP en cada reinicio de forma automática."

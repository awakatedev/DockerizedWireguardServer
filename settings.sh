#!/bin/bash

# Generar las claves del servidor y guardarlas en archivos
umask 077
wg genkey | tee /etc/wireguard/privatekey-server | wg pubkey > /etc/wireguard/publickey-server

# Leer las claves del servidor desde los archivos
SERVER_PRIVATEKEY=$(cat /etc/wireguard/privatekey-server)
SERVER_PUBLICKEY=$(cat /etc/wireguard/publickey-server)

# Crear el archivo de configuración wg0.conf para el servidor
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.0.0.1/23
ListenPort = 51820
PrivateKey = $SERVER_PRIVATEKEY

PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth+ -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth+ -j MASQUERADE

EOF

# Reiniciar la interfaz WireGuard
wg-quick down wg0
wg-quick up wg0

# Agregar la configuración para cada peer al archivo wg0.conf~
for i in $(seq 2 400); do
    # Crear la carpeta para el cliente
    mkdir -p config/peer$i

    # Generar las claves privadas y públicas para el cliente
    wg genkey | tee config/peer$i/privatekey-$i | wg pubkey > config/peer$i/publickey-$i
    wg genpsk > config/peer$i/presharedkey-$i

    # Leer las claves desde los archivos
    PUBLICKEY=$(cat config/peer$i/publickey-$i)
    PRIVATEKEY=$(cat config/peer$i/privatekey-$i)
    PRESHAREDKEY=$(cat config/peer$i/presharedkey-$i)

    # Calcular las partes de la dirección IP para el cliente
    IP_THIRD_OCTET=$(($i / 256))
    IP_FOURTH_OCTET=$(($i % 256))
    ALLOWEDIP="10.0.$IP_THIRD_OCTET.$IP_FOURTH_OCTET/32"
    SIMPLEALLOWEDIP="10.0.$IP_THIRD_OCTET.$IP_FOURTH_OCTET"

    echo "Private key for peer$i: $PRIVATEKEY"
    echo "Preshared key for peer$i: $PRESHAREDKEY"
    echo "Allowed IP for peer$i: $ALLOWEDIP"

    # Agregar el peer al servidor WireGuard
    wg set wg0 peer "$PUBLICKEY" allowed-ips "$ALLOWEDIP" preshared-key <(echo "$PRESHAREDKEY")
    
    # Añadir la configuración de cada peer a wg0.conf
    cat >> /etc/wireguard/wg0.conf <<EOF
[Peer]
PublicKey = $PUBLICKEY
AllowedIPs = $ALLOWEDIP
PresharedKey = $PRESHAREDKEY

EOF
    # Crear el archivo de configuración peer.conf para el cliente
    cat > config/peer$i/peer$i.conf <<EOF
[Interface]
Address = $SIMPLEALLOWEDIP
PrivateKey = $PRIVATEKEY
ListenPort = 51820

[Peer]
PublicKey = $SERVER_PUBLICKEY
PresharedKey = $PRESHAREDKEY
Endpoint = 3.74.92.200:51820
AllowedIPs = $ALLOWEDIP
EOF

    # Crear el código QR y guardar el PNG en la carpeta del cliente
    qrencode -t PNG -o config/peer$i/qr.png < config/peer$i/peer$i.conf

    ufw allow 22/tcp
    ufw allow 51820/udp
    ufw enable

    # Crear el comando SQL para insertar en la base de datos
    SQL="INSERT INTO \`keys\` (\`private_key\`, \`preshared_key\`, \`internal_ip\`) VALUES ('$PRIVATEKEY', '$PRESHAREDKEY', '$ALLOWEDIP');"

    echo "SQL for peer$i: $SQL"

    # Agregar la clave precompartida a la base de datos
    mysql --host=db-mysql-fra-vpn-do-user-13704052-0.b.db.ondigitalocean.com --user=doadmin --password=AVNS_T9P5F4hzWopCINJPLso --database=defaultdb --execute="$SQL"
done

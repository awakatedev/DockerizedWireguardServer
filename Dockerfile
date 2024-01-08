FROM linuxserver/wireguard

# Instala el cliente MySQL en el contenedor
RUN apk update && \
    apk add mysql-client && \
    rm -rf /var/cache/apk/*

# # Copia los scripts en el contenedor
# COPY ./key-creation.sh /app/key-creation.sh 
COPY ./setting-keys.sh /app/setting-keys.sh

# Otorga permisos de ejecución a los scripts
# RUN chmod +x /app/key-creation.sh 
RUN chmod +x /app/setting-keys.sh 

# Ejecuta los scripts al iniciar el contenedor
CMD /app/setting-keys.sh && /init

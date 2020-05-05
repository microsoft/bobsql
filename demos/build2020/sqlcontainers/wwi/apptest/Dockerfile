FROM mcr.microsoft.com/mssql-tools

COPY . /

RUN chmod +x /db-init.sh
CMD /bin/bash ./entrypoint.sh
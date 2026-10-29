FROM mcr.microsoft.com/mssql/rhel/server:2019-latest
RUN useradd -u 10001 -g root mssql
RUN mkdir -p -m 770 /var/opt/mssql && chgrp -R 0 /var/opt/mssql
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]
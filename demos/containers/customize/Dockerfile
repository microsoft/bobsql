FROM microsoft/mssql-server-linux:latest
COPY ./mssql.conf /
#COPY ./runsql.sh /
RUN mkdir /var/opt/mssql
RUN mv ./mssql.conf /var/opt/mssql
#RUN chmod u+x runsql.sh
CMD ["/opt/mssql/bin/sqlservr"]
#CMD ./runsql.sh

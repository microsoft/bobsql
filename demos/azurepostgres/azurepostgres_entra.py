import psycopg

# Azure PostgreSQL database configuration
database_config = {
    'host': 'bwpostgres.postgres.database.azure.com',
    'dbname': 'shakespeare',
    'user': 'bobward@microsoft.com',
    'password': 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IlQxU3QtZExUdnlXUmd4Ql82NzZ1OGtyWFMtSSIsImtpZCI6IlQxU3QtZExUdnlXUmd4Ql82NzZ1OGtyWFMtSSJ9.eyJhdWQiOiJodHRwczovL29zc3JkYm1zLWFhZC5kYXRhYmFzZS53aW5kb3dzLm5ldCIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzcyZjk4OGJmLTg2ZjEtNDFhZi05MWFiLTJkN2NkMDExZGI0Ny8iLCJpYXQiOjE3MDE4Nzc0MzIsIm5iZiI6MTcwMTg3NzQzMiwiZXhwIjoxNzAxODgyMzIxLCJfY2xhaW1fbmFtZXMiOnsiZ3JvdXBzIjoic3JjMSJ9LCJfY2xhaW1fc291cmNlcyI6eyJzcmMxIjp7ImVuZHBvaW50IjoiaHR0cHM6Ly9ncmFwaC53aW5kb3dzLm5ldC83MmY5ODhiZi04NmYxLTQxYWYtOTFhYi0yZDdjZDAxMWRiNDcvdXNlcnMvNmRhN2MyZGQtOGUyZS00NjlmLWEyMTYtYzM4NDMxMmUyYTJkL2dldE1lbWJlck9iamVjdHMifX0sImFjciI6IjEiLCJhaW8iOiJBWVFBZS84VkFBQUFZb0RHOFhqM0o1VFNNOFk3UGE2RXpYY1VsOFNUTWF6a1M0UDBnVjc0b2EzR1c0NVVCdmNMbUdYVTlRZnZUZEsvK0k1d0Z6ZzZnelBxVG52SHF3NzA5NjlMTWdFOWlqVCtaSCtVaEVkOTBoYjVBSHpNTENkaXk4VWFCUHB6SFVGTVhlbTVmeVhmaFhlcEJtaE5QNDBsQzZNTUdockg0RzBZeHpxTGtwVHRROGM9IiwiYW1yIjpbInJzYSIsIm1mYSJdLCJhcHBpZCI6ImI2NzdjMjkwLWNmNGItNGE4ZS1hNjBlLTkxYmE2NTBhNGFiZSIsImFwcGlkYWNyIjoiMCIsImRldmljZWlkIjoiNmUwY2QzYjMtYWNjZS00ZDU4LTkzYzEtMmU3NGJlZjYzYmM4IiwiZmFtaWx5X25hbWUiOiJXYXJkIiwiZ2l2ZW5fbmFtZSI6IkJvYiIsImlwYWRkciI6IjYzLjg1LjQuMjQiLCJuYW1lIjoiQm9iIFdhcmQiLCJvaWQiOiI2ZGE3YzJkZC04ZTJlLTQ2OWYtYTIxNi1jMzg0MzEyZTJhMmQiLCJvbnByZW1fc2lkIjoiUy0xLTUtMjEtMTI0NTI1MDk1LTcwODI1OTYzNy0xNTQzMTE5MDIxLTQ0MDYiLCJwdWlkIjoiMTAwMzAwMDA4MDFCRkYwQyIsInJoIjoiMC5BUm9BdjRqNWN2R0dyMEdScXkxODBCSGJSMURZUEJMZjJiMUFsTlhKOEh0X29nTWFBTTQuIiwic2NwIjoidXNlcl9pbXBlcnNvbmF0aW9uIiwic3ViIjoidlRJVW9HbGtmSmU3LU0wcUdZTzA3UUJ0Q2xKU1lJLUZJcVdfUjZNZnEyZyIsInRpZCI6IjcyZjk4OGJmLTg2ZjEtNDFhZi05MWFiLTJkN2NkMDExZGI0NyIsInVuaXF1ZV9uYW1lIjoiYm9id2FyZEBtaWNyb3NvZnQuY29tIiwidXBuIjoiYm9id2FyZEBtaWNyb3NvZnQuY29tIiwidXRpIjoiVXFMNVNmS3E0a3F5WnRxSmJkdEFBQSIsInZlciI6IjEuMCJ9.EsGA-Vyma6azT-IC_8v0zEz4JYwPf4insYVutSbBcq4TEp4OjYgwXp_tKjSFIZLlBAIssin4d_0ZSig82JjIvafsS-QHC6wh4m46tAbG42kKF2R3Y4k471CVQPm1kL6gVv_xZHtuGwOV07KpeMWl5wzMkVRznrhS3yQNlPgk1cRFx3cH2cRgGui-Vu4XbAXlrUKoqoZoCaI8X-SJFxO_vkTDCsblSBoml2B11cE_aqNAIRHit_h47jXdZeXmzEsmp-Ous8_FXr9kYrQQEzEXJW3KsWl0ZI428tjW_saLhpY0ul6ozhJYghm2xl_EtXklGK4BkNyCQz_ejG_4DKkqhA',
    'port': '5432',  # Change it if your PostgreSQL server uses a different port
    'sslmode': 'require',  # Use 'require' for SSL connection
}

# SQL query to execute
query = """
SELECT ch.name FROM 
shakespeare.character ch
JOIN shakespeare.character_work cw
ON ch.id = cw.character_id
JOIN shakespeare.work w
ON cw.work_id = w.id
AND w.title = 'Hamlet';
"""

def execute_query(connection, query):
    with connection.cursor() as cursor:
        cursor.execute(query)
        result = cursor.fetchall()
        return result

try:
    # Establish a connection to the Azure PostgreSQL database
    connection = psycopg.connect(**database_config)

    # Execute the query
    result_set = execute_query(connection, query)

    # Process the results
    for row in result_set:
        print(row)

except Exception as e:
    print(f"Error: {e}")

finally:
    # Close the database connection
    if connection:
        connection.close()

import psycopg

# Azure PostgreSQL database configuration
database_config = {
    'host': 'bwpostgres.postgres.database.azure.com',
    'dbname': 'shakespeare',
    'user': 'bobward@microsoft.com',
    'password': 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6IlQxU3QtZExUdnlXUmd4Ql82NzZ1OGtyWFMtSSIsImtpZCI6IlQxU3QtZExUdnlXUmd4Ql82NzZ1OGtyWFMtSSJ9.eyJhdWQiOiJodHRwczovL29zc3JkYm1zLWFhZC5kYXRhYmFzZS53aW5kb3dzLm5ldCIsImlzcyI6Imh0dHBzOi8vc3RzLndpbmRvd3MubmV0LzcyZjk4OGJmLTg2ZjEtNDFhZi05MWFiLTJkN2NkMDExZGI0Ny8iLCJpYXQiOjE3MDEzMTgzOTcsIm5iZiI6MTcwMTMxODM5NywiZXhwIjoxNzAxMzIzMzU2LCJfY2xhaW1fbmFtZXMiOnsiZ3JvdXBzIjoic3JjMSJ9LCJfY2xhaW1fc291cmNlcyI6eyJzcmMxIjp7ImVuZHBvaW50IjoiaHR0cHM6Ly9ncmFwaC53aW5kb3dzLm5ldC83MmY5ODhiZi04NmYxLTQxYWYtOTFhYi0yZDdjZDAxMWRiNDcvdXNlcnMvNmRhN2MyZGQtOGUyZS00NjlmLWEyMTYtYzM4NDMxMmUyYTJkL2dldE1lbWJlck9iamVjdHMifX0sImFjciI6IjEiLCJhaW8iOiJBWVFBZS84VkFBQUFyUWlPQ3VjbWsrSHd0VDQ0clM4OUtnN2dkOUxEekxGdXYyNGJkZUR3TWNsbkpSUVhaZ0ZzTm95UEFvZDE1bU5QRnprTTFPRFJpNEJPSWxrWWN1WThZODhmVFZPd216dFNuVmlaNkowWHdyb2tOTkZFMGtKalVxbU8vS2N6UUF5ZjV5RlIzeVlWcG9pSEtNTkV1K3pYMWRreHB2M1hMZWswSUNSMHFBQ3pKVGM9IiwiYW1yIjpbInJzYSIsIm1mYSJdLCJhcHBpZCI6ImI2NzdjMjkwLWNmNGItNGE4ZS1hNjBlLTkxYmE2NTBhNGFiZSIsImFwcGlkYWNyIjoiMCIsImRldmljZWlkIjoiNmUwY2QzYjMtYWNjZS00ZDU4LTkzYzEtMmU3NGJlZjYzYmM4IiwiZmFtaWx5X25hbWUiOiJXYXJkIiwiZ2l2ZW5fbmFtZSI6IkJvYiIsImlwYWRkciI6IjcxLjExLjI0Mi4xMzkiLCJuYW1lIjoiQm9iIFdhcmQiLCJvaWQiOiI2ZGE3YzJkZC04ZTJlLTQ2OWYtYTIxNi1jMzg0MzEyZTJhMmQiLCJvbnByZW1fc2lkIjoiUy0xLTUtMjEtMTI0NTI1MDk1LTcwODI1OTYzNy0xNTQzMTE5MDIxLTQ0MDYiLCJwdWlkIjoiMTAwMzAwMDA4MDFCRkYwQyIsInJoIjoiMC5BUm9BdjRqNWN2R0dyMEdScXkxODBCSGJSMURZUEJMZjJiMUFsTlhKOEh0X29nTWFBTTQuIiwic2NwIjoidXNlcl9pbXBlcnNvbmF0aW9uIiwic3ViIjoidlRJVW9HbGtmSmU3LU0wcUdZTzA3UUJ0Q2xKU1lJLUZJcVdfUjZNZnEyZyIsInRpZCI6IjcyZjk4OGJmLTg2ZjEtNDFhZi05MWFiLTJkN2NkMDExZGI0NyIsInVuaXF1ZV9uYW1lIjoiYm9id2FyZEBtaWNyb3NvZnQuY29tIiwidXBuIjoiYm9id2FyZEBtaWNyb3NvZnQuY29tIiwidXRpIjoid1c2cUJoV2JIay0ycW9MeFBoc3ZBZyIsInZlciI6IjEuMCJ9.hXLuhKTQbER7exwGa1-9mzKkGsKlobDFtyTwvxsHi8mPW7upgA7phkbeJRoUNjGGLmN75ForgucNwzIp9I84RlQ2mKaRYM568-Ci2jZQisTCQS2WBPBa7RKY8sF04ENgRFKSB8hQnKCSZPk5Jrj0OtqE4uZw2TnxJlhH31jdc_A24MrckzdLIa-O1CdeAUEuT1mJ_busCj8Vn9Erem77z-1R2pCbwTKGMxfr7Yd57RZ27I2BpbNd2mOWKw9TEvIeIwaKF7K8EiodSITo95MTmjyvKR5PuuiqBCEtk8g8aNG1VX-y-A9kgtWFOfoVoOxmYKL56AxDQRsIzX5-h19Ipg',
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

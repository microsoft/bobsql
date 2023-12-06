import psycopg

# Azure PostgreSQL database configuration
database_config = {
    'host': 'bwpostgres.postgres.database.azure.com',
    'dbname': 'shakespeare',
    'user': 'pguser',
    'password': 'Strongpassw0rd!',
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

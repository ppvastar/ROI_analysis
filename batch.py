import sqlalchemy

engine = sqlalchemy.create_engine("postgresql://pengzhang:password@host:port/schema")

path="cost_revenue_data.sql"
file = open(path)

sql_query = sqlalchemy.text(file.read())

con = engine.connect()
con.execute(sql_query)
con.close()

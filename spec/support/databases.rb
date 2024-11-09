module Databases
  extend self

  def connect_to_sqlite
    ActiveRecord::Base.establish_connection(
      adapter:  "sqlite3",
      database: ":memory:"
    )
    load("support/models.rb")
  end

  def connect_to_postgres
    ActiveRecord::Base.establish_connection(
      adapter:  "postgresql",
      host: ENV.fetch('DB_HOST', 'localhost'),
      username: ENV.fetch("POSTGRES_USER", 'active_record_union'),
      password: ENV.fetch("POSTGRES_PASSWORD", 'active_record_union')
    )
    try_to_drop_database
    ActiveRecord::Base.connection.create_database("test_active_record_union")
    ActiveRecord::Base.establish_connection(
      adapter:  "postgresql",
      host: ENV.fetch('DB_HOST', 'localhost'),
      username: ENV.fetch("POSTGRES_USER", 'active_record_union'),
      password: ENV.fetch("POSTGRES_PASSWORD", 'active_record_union'),
      database: ENV.fetch("POSTGRES_DB", "test_active_record_union")
    )
    load("support/models.rb")
  end

  def try_to_drop_database
    ActiveRecord::Base.connection.drop_database("test_active_record_union")
  rescue ActiveRecord::NoDatabaseError
    $stderr.puts "Can't drop database 'test_active_record_union' as it doesn't exist"
  rescue ActiveRecord::ActiveRecordError => e
    $stderr.puts "Can't drop database 'test_active_record_union' (but continuing anyway): #{e}"
  rescue => e
    $stderr.puts "Other error (#{e.class.name}) dropping database 'test_active_record_union' (but continuing anyway): #{e}"
  end

  def connect_to_mysql
    ActiveRecord::Base.establish_connection(
      adapter:  "mysql2",
      host: ENV.fetch('DB_HOST', 'localhost'),
      username: ENV.fetch("MYSQL_USER", "active_record_union"),
      password: ENV.fetch("MYSQL_PASSWORD", "active_record_union")
    )
    ActiveRecord::Base.connection.recreate_database("test_active_record_union")
    ActiveRecord::Base.establish_connection(
      adapter:  "mysql2",
      host: ENV.fetch('DB_HOST', 'localhost'),
      username: ENV.fetch("MYSQL_USER", "active_record_union"),
      password: ENV.fetch("MYSQL_PASSWORD", "active_record_union"),
      database: ENV.fetch("MYSQL_DB", "test_active_record_union")
    )
    load("support/models.rb")
  end

  def with_postgres(&block)
    connect_to_postgres
    yield
  ensure
    connect_to_sqlite
  end

  def with_mysql(&block)
    connect_to_mysql
    yield
  ensure
    connect_to_sqlite
  end
end

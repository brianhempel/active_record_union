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
      adapter:  "postgresql"
    )
    ActiveRecord::Base.connection.execute('CREATE DATABASE "test_active_record_union"') rescue nil
    ActiveRecord::Base.establish_connection(
      adapter:  "postgresql",
      database: "test_active_record_union"
    )
    load("support/models.rb")
  end

  def connect_to_mysql
    ActiveRecord::Base.establish_connection(
      adapter:  "mysql"
    )
    ActiveRecord::Base.connection.execute('CREATE DATABASE test_active_record_union') rescue nil
    ActiveRecord::Base.establish_connection(
      adapter:  "mysql",
      database: "test_active_record_union"
    )
    load("support/models.rb")
  end

  def with_postgres(&block)
    connect_to_postgres
  ensure
    connect_to_sqlite
  end

  def with_mysql(&block)
    connect_to_mysql
  ensure
    connect_to_sqlite
  end
end
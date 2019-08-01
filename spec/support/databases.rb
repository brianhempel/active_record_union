module Databases
  extend self

  def connect_to_sqlite
    ActiveRecord::Base.establish_connection(
      adapter:  'sqlite3',
      database: ':memory:'
    )
    load('support/models.rb')
  end

  def connect_to_postgres
    ActiveRecord::Base.establish_connection(
      adapter:  'postgresql'
    )
    ActiveRecord::Base.connection.recreate_database('test_active_record_union')
    ActiveRecord::Base.establish_connection(
      adapter:  'postgresql',
      database: 'test_active_record_union'
    )
    load('support/models.rb')
  end

  def connect_to_mysql
    ActiveRecord::Base.establish_connection(
      adapter:  'mysql2',
      username: 'travis'
    )
    ActiveRecord::Base.connection.recreate_database('test_active_record_union')
    ActiveRecord::Base.establish_connection(
      adapter:  'mysql2',
      database: 'test_active_record_union',
      username: 'travis'
    )
    load('support/models.rb')
  end

  def with_postgres
    connect_to_postgres
    yield
  ensure
    connect_to_sqlite
  end

  def with_mysql
    connect_to_mysql
    yield
  ensure
    connect_to_sqlite
  end
end

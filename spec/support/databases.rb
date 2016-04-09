module Databases
  extend self

  DEFAULT_CONFIG = {
      username:     ENV.fetch('DB_USER', 'ar_union_gem'),
      password:     ENV.fetch('DB_PASS', 'ar_union_gem'),
      host:         '127.0.0.1',
      database:     'test_active_record_union',
      encoding:     'utf8',
      min_messages: 'WARNING',
  }

  def connect_to_sqlite
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    load('support/models.rb')
  end

  def connect_to_postgres
    create_db_and_connect DEFAULT_CONFIG.merge(adapter: 'postgresql')
  end

  def connect_to_mysql
    create_db_and_connect DEFAULT_CONFIG.merge(adapter: 'mysql2')
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

  private

  def create_db_and_connect(config)
    ActiveRecord::Tasks::DatabaseTasks.create(config.stringify_keys)
    ActiveRecord::Base.establish_connection(config)
    load('support/models.rb')
  end
end

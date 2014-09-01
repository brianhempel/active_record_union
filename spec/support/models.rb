class User < ActiveRecord::Base
  connection.create_table :users, force: true do |t|
  end

  has_many :posts
end

class Post < ActiveRecord::Base
  connection.create_table :posts, force: true do |t|
    t.integer   :user_id
    t.timestamp :published_at
    t.timestamps
  end

  belongs_to :user
end

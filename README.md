# ActiveRecordUnion

Use unions on ActiveRecord scopes without ugliness.

## Installation

Add this line to your application's Gemfile:

    gem 'active_record_union'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install active_record_union

## Usage

ActiveRecordUnion adds a `union` method to `ActiveRecord::Relation` so you can easily gather together queries on mutiple scopes.

```ruby
class User < ActiveRecord::Base
  has_many :posts
end

class Post < ActiveRecord::Base
  belongs_to :user

  scope :published, -> { where("published_at < ?", Time.now) }
end

current_user.posts.union(Post.published)
```

Which is equivalent to the following SQL (for SQLite):

```sql
SELECT "posts".* FROM (
  SELECT "posts".* FROM "posts"  WHERE "posts"."user_id" = ?
  UNION
  SELECT "posts".* FROM "posts"  WHERE (published_at < '2014-07-19 16:04:21.918366')
) posts
```
(Note: the `?` in the above is bound to the correct value when ActiveRecord executes the query.)

Because `union` returns another `ActiveRecord::Relation`, you can run further queries on the union.

```ruby
current_user.posts.union(Post.published).where(id: [6, 7])
```
```sql
SELECT "posts".* FROM (
  SELECT "posts".* FROM "posts"  WHERE "posts"."user_id" = ?
  UNION
  SELECT "posts".* FROM "posts"  WHERE (published_at < '2014-07-19 16:06:04.460771')
) posts  WHERE "posts"."id" IN (6, 7)
```

Besides taking a relation, the `union` method also accepts anything that `where` does.

```ruby
current_user.posts.union("published_at < ?", Time.now)
# equivalent to...
current_user.posts.union(Post.where("published_at < ?", Time.now))
```

You can also chain `union` calls to UNION more than two scopes, though the UNIONs will be nested which may not be the prettiest SQL.

```
user_1.posts.union(user_2.posts).union(Post.published)
# equivalent to...
[user_1.posts, user_2.posts, Post.published].inject(:union)
```
```sql
SELECT "posts".* FROM (
  SELECT "posts".* FROM (
    SELECT "posts".* FROM "posts"  WHERE "posts"."user_id" = ?
    UNION
    SELECT "posts".* FROM "posts"  WHERE "posts"."user_id" = ?
  ) posts
  UNION
  SELECT "posts".* FROM "posts"  WHERE (published_at < '2014-07-19 16:12:45.882648')
) posts
```

## Another nifty way to reduce extra queries

ActiveRecord already supports turning scopes into nested queries in WHERE clauses. The nested relation defaults to selecting `id` by default.

For example, if a User `has_and_belongs_to_many :favorited_posts`, we can quickly find which of the current user's posts are liked by a certain other user.

```ruby
current_user.posts.where(id: other_user.favorited_posts)
```
```sql
SELECT "posts".* FROM "posts"
  WHERE "posts"."user_id" = ?
  AND "posts"."id" IN (
    SELECT "posts"."id"
      FROM "posts" INNER JOIN "user_favorited_posts" ON "posts"."id" = "user_favorited_posts"."post_id"
      WHERE "user_favorited_posts"."user_id" = ?
  )
```

If you want to select something other than `id`, use `select` to specify. The following is equivalent to the above, but the query is done against the join table.

```ruby
current_user.posts.where(id: UserFavoritedPost.where(user_id: other_user.id).select(:post_id))
```
```sql
SELECT "posts".* FROM "posts"
  WHERE "posts"."user_id" = ?
  AND "posts"."id" IN (
    SELECT "user_favorited_posts"."post_id"
      FROM "user_favorited_posts"
      WHERE "user_favorited_posts"."user_id" = 2
  )
```

(The above example is illustrative only. It might be better with a JOIN.)

## State of the Union in ActiveRecord

Why does this gem exist?

Right now in ActiveRecord, if you call `scope.union` you get an `Arel::Nodes::Union` object instead of an `ActiveRecord::Relation`.

You could call `to_sql` on the Arel object and then use `find_by_sql`, but that's super clean and if the original scopes included an association, then the `to_sql` may produce a query with values that need to be bound (`?`s) and you have to provide those yourself. (E.g. `user.posts.to_sql` produces `SELECT "posts".* FROM "posts"  WHERE "posts"."user_id" = ?`.)

While ActiveRecord may sometime have the ability to cleanly perform UNIONs, it's currently stalled. If your interested, the relevant URLs as of July 2014 are:

https://github.com/rails/rails/issues/939 and
https://github.com/rails/arel/pull/239 and
https://github.com/yakaz/rails/commit/29b8ebd187e0888d5e71b2e1e4a12334860bc76c

This is a gem not a Rails pull request because the standard of code quality for a PR is a bit higher, and you'd have to wait for the PR to be merged and relased to use it. That said, the code here is fairly clean and it may end up in a PR sometime.

## License

ActiveRecordUnion is dedicated to the public domain by its author, Brian Hempel. No rights are reserved. No restrictions are placed on the use of ActiveRecordUnion. That freedom also means, of course, that no warrenty of fitness is claimed; use ActiveRecordUnion at your own risk.

Public domain dedication is explained by the CC0 1.0 summary (and only the summary) at https://creativecommons.org/publicdomain/zero/1.0/

## Contributing

1. Fork it ( https://github.com/[my-github-username]/active_record_union/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Run the tests with `rspec`
4. There is also a `bin/console` command to load up a REPL for playing around
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin my-new-feature`)
7. Create a new Pull Request

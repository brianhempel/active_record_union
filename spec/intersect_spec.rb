require 'spec_helper'

describe ActiveRecord::Relation do
  TIME     = Time.utc(2014, 7, 19, 0, 0, 0)
  SQL_TIME = ActiveRecord::VERSION::MAJOR >= 5 ? '2014-07-19 00:00:00' : '2014-07-19 00:00:00.000000'

  describe '.intersect' do
    it 'returns an ActiveRecord::Relation' do
      expect(User.all.intersect(User.all)).to be_kind_of(ActiveRecord::Relation)
    end

    it 'requires an argument' do
      expect { User.all.intersect }.to raise_error(ArgumentError)
    end

    it 'explodes if asked to intersect a relation with includes' do
      expect { User.all.intersect(User.includes(:posts)) }.to raise_error(ArgumentError)
      expect { User.includes(:posts).intersect(User.all) }.to raise_error(ArgumentError)
    end

    it 'explodes if asked to intersect a relation with preload values' do
      expect { User.all.intersect(User.preload(:posts)) }.to raise_error(ArgumentError)
      expect { User.preload(:posts).intersect(User.all) }.to raise_error(ArgumentError)
    end

    it 'explodes if asked to intersect a relation with eager loading' do
      expect { User.all.intersect(User.eager_load(:posts)) }.to raise_error(ArgumentError)
      expect { User.eager_load(:posts).intersect(User.all) }.to raise_error(ArgumentError)
    end

    it 'works' do
      intersect = User.new(id: 1).posts.intersect(Post.where('created_at > ?', TIME))

      expect(intersect.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 INTERSECT SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
      )
      expect(intersect.arel.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = ? INTERSECT SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
      )
      expect { intersect.to_a }.to_not raise_error
    end

    def bind_values_from_relation(relation)
      if ActiveRecord.gem_version >= Gem::Version.new('5.2.0.beta2')
        relation.arel_table.class.engine.connection.visitor.accept(
          relation.arel.ast, Arel::Collectors::Bind.new
        ).value.map(&:value)
      elsif ActiveRecord::VERSION::MAJOR >= 5
        relation.bound_attributes.map(&:value_for_database)
      else
        (relation.arel.bind_values + relation.bind_values).map { |_column, value| value }
      end
    end

    it 'binds values properly' do
      user1 = User.new(id: 1)
      user2 = User.new(id: 2)
      user3 = User.new(id: 3)

      intersect = user1.posts.intersect(user2.posts).where.not(id: user3.posts)

      # Inside ActiveRecord the bind value list is
      # (intersect.arel.bind_values + intersect.bind_values)
      bind_values = bind_values_from_relation intersect

      expect(bind_values).to eq([1, 2, 3])
    end

    it 'binds values properly on joins' do
      intersect = User.joins(:drafts).intersect(User.where(id: 11))

      bind_values = bind_values_from_relation intersect
      expect(bind_values).to eq([true, 11])

      expect(intersect.to_sql.squish).to eq(
        "SELECT \"users\".* FROM ( SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON \"posts\".\"user_id\" = \"users\".\"id\" AND \"posts\".\"draft\" = 't' INTERSECT SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" = 11 ) \"users\""
      )
      expect { intersect.to_a }.to_not raise_error
    end

    it "doesn't repeat default scopes" do
      expect(Time).to receive(:now) { Time.utc(2014, 7, 24, 0, 0, 0) }
      sql_now = "2014-07-24 00:00:00#{'.000000' if ActiveRecord::VERSION::MAJOR < 5}"

      class PublishedPost < ActiveRecord::Base
        self.table_name = 'posts'
        default_scope { where('published_at < ?', Time.now) }
      end

      intersect = PublishedPost.where('created_at > ?', TIME).intersect(User.new(id: 1).posts)

      expect(intersect.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE (published_at < '#{sql_now}') AND (created_at > '#{SQL_TIME}') INTERSECT SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ) \"posts\""
      )
      expect { intersect.to_a }.to_not raise_error
    end

    context 'with ORDER BY in subselects' do
      let :intersect do
        User.new(id: 1).posts.order(:created_at).intersect(
          Post.where('created_at > ?', TIME).order(:created_at)
        ).order(:created_at)
      end

      context 'in SQLite' do
        it 'lets ORDER BY in query subselects throw a syntax error' do
          if ([ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR] <=> [5, 2]) >= 0
            expect(intersect.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC INTERSECT SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00') ORDER BY \"posts\".\"created_at\" ASC ) \"posts\" ORDER BY \"created_at\" ASC"
            )
          else
            expect(intersect.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC INTERSECT SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ORDER BY \"posts\".\"created_at\" ASC ) \"posts\" ORDER BY \"posts\".\"created_at\" ASC"
            )
          end
          expect { intersect.to_a }.to raise_error(ActiveRecord::StatementInvalid)
        end
      end

      context 'in Postgres' do
        it 'wraps query subselects in parentheses to allow ORDER BY clauses' do
          Databases.with_postgres do
            if ([ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR] <=> [5, 2]) >= 0
              expect(intersect.to_sql.squish).to eq(
                "SELECT \"posts\".* FROM ( (SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC) INTERSECT (SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00') ORDER BY \"posts\".\"created_at\" ASC) ) \"posts\" ORDER BY \"created_at\" ASC"
              )
            else
              expect(intersect.to_sql.squish).to eq(
                "SELECT \"posts\".* FROM ( (SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC) INTERSECT (SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ORDER BY \"posts\".\"created_at\" ASC) ) \"posts\" ORDER BY \"posts\".\"created_at\" ASC"
              )
            end
            expect { intersect.to_a }.to_not raise_error
          end
        end
      end

      context 'in MySQL' do
        it 'wraps query subselects in parentheses to allow ORDER BY clauses' do
          Databases.with_mysql do
            if ([ActiveRecord::VERSION::MAJOR, ActiveRecord::VERSION::MINOR] <=> [5, 2]) >= 0
              expect(intersect.to_sql.squish).to eq(
                "SELECT `posts`.* FROM ( (SELECT `posts`.* FROM `posts` WHERE `posts`.`user_id` = 1 ORDER BY `posts`.`created_at` ASC) INTERSECT (SELECT `posts`.* FROM `posts` WHERE (created_at > '2014-07-19 00:00:00') ORDER BY `posts`.`created_at` ASC) ) `posts` ORDER BY `created_at` ASC"
              )
            else
              expect(intersect.to_sql.squish).to eq(
                "SELECT `posts`.* FROM ( (SELECT `posts`.* FROM `posts` WHERE `posts`.`user_id` = 1 ORDER BY `posts`.`created_at` ASC) INTERSECT (SELECT `posts`.* FROM `posts` WHERE (created_at > '#{SQL_TIME}') ORDER BY `posts`.`created_at` ASC) ) `posts` ORDER BY `posts`.`created_at` ASC"
              )
            end
            expect { intersect.to_a }.to_not raise_error
          end
        end
      end
    end

    context 'builds a scope when given' do
      it 'a hash' do
        intersect = User.new(id: 1).posts.intersect(id: 2)

        expect(intersect.to_sql.squish).to eq(
          'SELECT "posts".* FROM ( SELECT "posts".* FROM "posts" WHERE "posts"."user_id" = 1 INTERSECT SELECT "posts".* FROM "posts" WHERE "posts"."id" = 2 ) "posts"'
        )
        expect { intersect.to_a }.to_not raise_error
      end

      it 'multiple arguments' do
        intersect = User.new(id: 1).posts.intersect('created_at > ?', TIME)

        expect(intersect.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 INTERSECT SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
        )
        expect { intersect.to_a }.to_not raise_error
      end

      it 'arel' do
        intersect = User.new(id: 1).posts.intersect(Post.arel_table[:id].eq(2).or(Post.arel_table[:id].eq(3)))

        expect(intersect.to_sql.squish).to eq(
          'SELECT "posts".* FROM ( SELECT "posts".* FROM "posts" WHERE "posts"."user_id" = 1 INTERSECT SELECT "posts".* FROM "posts" WHERE ("posts"."id" = 2 OR "posts"."id" = 3) ) "posts"'
        )
        expect { intersect.to_a }.to_not raise_error
      end
    end
  end
end

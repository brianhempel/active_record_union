require "spec_helper"

describe ActiveRecord::Relation do
  TIME     = Time.utc(2014, 7, 19, 0, 0, 0)
  SQL_TIME = "2014-07-19 00:00:00"

  describe ".union" do
    it "returns an ActiveRecord::Relation" do
      expect(User.all.union(User.all)).to be_kind_of(ActiveRecord::Relation)
    end

    it "requires an argument" do
      expect{User.all.union}.to raise_error(ArgumentError)
    end

    it "explodes if asked to union a relation with includes" do
      expect{User.all.union(User.includes(:posts))}.to raise_error(ArgumentError)
      expect{User.includes(:posts).union(User.all)}.to raise_error(ArgumentError)
    end

    it "explodes if asked to union a relation with preload values" do
      expect{User.all.union(User.preload(:posts))}.to raise_error(ArgumentError)
      expect{User.preload(:posts).union(User.all)}.to raise_error(ArgumentError)
    end

    it "explodes if asked to union a relation with eager loading" do
      expect{User.all.union(User.eager_load(:posts))}.to raise_error(ArgumentError)
      expect{User.eager_load(:posts).union(User.all)}.to raise_error(ArgumentError)
    end

    it "works" do
      union = User.new(id: 1).posts.union(Post.where("created_at > ?", TIME))

      expect(union.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
      )
      if ActiveRecord.version >= Gem::Version.new("7.2.0")
        expect(union.arel.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = ? UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > ?) ) \"posts\""
        )
        expect(bind_values_from_arel(union.arel, Post.arel_table)).to eq([1, TIME])
      else
        expect(union.arel.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = ? UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
        )
        expect(bind_values_from_arel(union.arel, Post.arel_table)).to eq([1])
      end
      expect { union.to_a }.to_not raise_error
    end

    def bind_values_from_relation(relation)
      bind_values_from_arel(relation.arel, relation.arel_table)
    end

    def bind_values_from_arel(arel, arel_table)
      collector = Arel::Collectors::Bind.new
      collector.define_singleton_method(:preparable=) { |_preparable| } if ActiveRecord.version.between?(Gem::Version.new("6.1.0"), Gem::Version.new("7.2.99"))
      arel_table.class.engine.connection.visitor.accept(
        arel.ast, collector
      ).value.map { |v| v.try(:value) || v }
    end

    it "binds values properly" do
      user1 = User.new(id: 1)
      user2 = User.new(id: 2)
      user3 = User.new(id: 3)

      union = user1.posts.union(user2.posts).where.not(id: user3.posts)

      # Inside ActiveRecord the bind value list is
      # (union.arel.bind_values + union.bind_values)
      bind_values = bind_values_from_relation union

      expect(bind_values).to eq([1, 2, 3])
    end

    it "binds values properly on joins" do
      union = User.joins(:drafts).union(User.where(id: 11))

      bind_values = bind_values_from_relation union
      expect(bind_values).to eq([true, 11])

      expect(union.to_sql.squish).to eq(
        "SELECT \"users\".* FROM ( SELECT \"users\".* FROM \"users\" INNER JOIN \"posts\" ON \"posts\".\"draft\" = 1 AND \"posts\".\"user_id\" = \"users\".\"id\" UNION SELECT \"users\".* FROM \"users\" WHERE \"users\".\"id\" = 11 ) \"users\""
      )
      expect{union.to_a}.to_not raise_error
    end

    it "doesn't repeat default scopes" do
      expect(Time).to receive(:now) { Time.utc(2014, 7, 24, 0, 0, 0) }

      sql_now = "2014-07-24 00:00:00"

      class PublishedPost < ActiveRecord::Base
        self.table_name = "posts"
        default_scope { where("published_at < ?", Time.now) }
      end

      union = PublishedPost.where("created_at > ?", TIME).union(User.new(id: 1).posts)

      expect(union.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE (published_at < '#{sql_now}') AND (created_at > '#{SQL_TIME}') UNION SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ) \"posts\""
      )
      expect{union.to_a}.to_not raise_error
    end

    context "with ORDER BY in subselects" do
      let :union do
        User.new(id: 1).posts.order(:created_at).union(
          Post.where("created_at > ?", TIME).order(:created_at)
        ).order(:created_at)
      end

      context "in SQLite" do
        it "lets ORDER BY in query subselects throw a syntax error" do
          if ActiveRecord.version >= Gem::Version.new("7.2.0")
            expect(union.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( (SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC) UNION (SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00') ORDER BY \"posts\".\"created_at\" ASC) ) \"posts\" ORDER BY \"created_at\" ASC"
            )
          else
            expect(union.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00') ORDER BY \"posts\".\"created_at\" ASC ) \"posts\" ORDER BY \"created_at\" ASC"
            )
          end
          expect{union.to_a}.to raise_error(ActiveRecord::StatementInvalid)
        end
      end

      context "in Postgres" do
        it "wraps query subselects in parentheses to allow ORDER BY clauses" do
          Databases.with_postgres do
            expect(union.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( (SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC) UNION (SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00') ORDER BY \"posts\".\"created_at\" ASC) ) \"posts\" ORDER BY \"created_at\" ASC"
            )

            expect{union.to_a}.to_not raise_error
          end
        end
      end

      context "in MySQL" do
        it "wraps query subselects in parentheses to allow ORDER BY clauses" do
          Databases.with_mysql do
            expect(union.to_sql.squish).to eq(
              "SELECT `posts`.* FROM ( (SELECT `posts`.* FROM `posts` WHERE `posts`.`user_id` = 1 ORDER BY `posts`.`created_at` ASC) UNION (SELECT `posts`.* FROM `posts` WHERE (created_at > '2014-07-19 00:00:00') ORDER BY `posts`.`created_at` ASC) ) `posts` ORDER BY `created_at` ASC"
            )

            expect{union.to_a}.to_not raise_error
          end
        end
      end
    end

    context "builds a scope when given" do
      it "a hash" do
        union = User.new(id: 1).posts.union(id: 2)

        expect(union.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = 2 ) \"posts\""
        )
        expect{union.to_a}.to_not raise_error
      end

      it "multiple arguments" do
        union = User.new(id: 1).posts.union("created_at > ?", TIME)

        expect(union.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
        )
        expect{union.to_a}.to_not raise_error
      end

      it "arel" do
        union = User.new(id: 1).posts.union(Post.arel_table[:id].eq(2).or(Post.arel_table[:id].eq(3)))

        expect(union.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE (\"posts\".\"id\" = 2 OR \"posts\".\"id\" = 3) ) \"posts\""
        )
        expect{union.to_a}.to_not raise_error
      end
    end
  end

  describe ".union_all" do
    it "works" do
      union = User.new(id: 1).posts.union_all(Post.where("created_at > ?", TIME))

      expect(union.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION ALL SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '#{SQL_TIME}') ) \"posts\""
      )
      expect{union.to_a}.to_not raise_error
    end
  end
end

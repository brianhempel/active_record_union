require 'spec_helper'

describe ActiveRecord::Relation do
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
      union = User.new(id: 1).posts.union(Post.where("created_at > ?", Time.utc(2014, 7, 19, 0, 0, 0)))

      expect(union.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00.000000') ) \"posts\""
      )
      expect(union.arel.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = ? UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00.000000') ) \"posts\""
      )
      expect{union.to_a}.to_not raise_error
    end

    it "binds values properly" do
      user1 = User.new(id: 1)
      user2 = User.new(id: 2)
      user3 = User.new(id: 3)

      union = user1.posts.union(user2.posts).where.not(id: user3.posts)
      bind_values = union.bind_values.map { |column, value| value }

      expect(bind_values).to eq([1, 2, 3])
    end

    it "doesn't repeat default scopes" do
      expect(Time).to receive(:now) { Time.utc(2014, 7, 24, 0, 0, 0) }

      class PublishedPost < ActiveRecord::Base
        self.table_name = "posts"
        default_scope { where("published_at < ?", Time.now) }
      end

      union = PublishedPost.where("created_at > ?", Time.utc(2014, 7, 19, 0, 0, 0)).union(User.new(id: 1).posts)

      expect(union.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE (published_at < '2014-07-24 00:00:00.000000') AND (created_at > '2014-07-19 00:00:00.000000') UNION SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ) \"posts\""
      )
      expect{union.to_a}.to_not raise_error
    end

    context "with ORDER BY in subselects" do
      def union
        User.new(id: 1).posts.order(:created_at).union(
          Post.where("created_at > ?", Time.utc(2014, 7, 19, 0, 0, 0)).order(:created_at)
        ).order(:created_at)
      end

      context "in SQLite" do
        it "lets ORDER BY in query subselects throw a syntax error" do
          expect(union.to_sql.squish).to eq(
            "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 ORDER BY \"posts\".\"created_at\" ASC UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00.000000') ORDER BY \"posts\".\"created_at\" ASC ) \"posts\" ORDER BY \"posts\".\"created_at\" ASC"
          )
          expect{union.to_a}.to raise_error(ActiveRecord::StatementInvalid)
        end
      end

      context "in Postgres" do
        it "wraps query subselects in parentheses to allow ORDER BY clauses" do
          Databases.with_postgres do
            expect(union.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( (SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = $1 ORDER BY \"posts\".\"created_at\" ASC) UNION (SELECT \"posts\".* FROM \"posts\"  WHERE (created_at > '2014-07-19 00:00:00.000000') ORDER BY \"posts\".\"created_at\" ASC) ) \"posts\" ORDER BY \"posts\".\"created_at\" ASC"
            )
            expect{union.to_a}.to_not raise_error
          end
        end
      end

      context "in MySQL" do
        it "wraps query subselects in parentheses to allow ORDER BY clauses" do
          Databases.with_mysql do
            expect(union.to_sql.squish).to eq(
              "SELECT \"posts\".* FROM ( (SELECT \"posts\".* FROM \"posts\"  WHERE \"posts\".\"user_id\" = $1  ORDER BY \"posts\".\"created_at\" ASC) UNION (SELECT \"posts\".* FROM \"posts\"  WHERE (created_at > '2014-07-19 00:00:00.000000')  ORDER BY \"posts\".\"created_at\" ASC) ) \"posts\"   ORDER BY \"posts\".\"created_at\" ASC"
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
      end

      it "multiple arguments" do
        union = User.new(id: 1).posts.union("created_at > ?", Time.utc(2014, 7, 19, 0, 0, 0))

        expect(union.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00.000000') ) \"posts\""
        )
      end

      it "arel" do
        union = User.new(id: 1).posts.union(Post.arel_table[:id].eq(2).or(Post.arel_table[:id].eq(3)))

        expect(union.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE (\"posts\".\"id\" = 2 OR \"posts\".\"id\" = 3) ) \"posts\""
        )
      end

      it "multiple relations" do
        union = User.new(id: 1).posts.union(Post.where(id: 2), Post.where(id: 3), Post.where(id: 4))

        expect(union.to_sql.squish).to eq(
          "SELECT \"posts\".* FROM ( ( ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = 2 ) UNION SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = 3 ) UNION SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"id\" = 4 ) \"posts\""
        )
      end
    end
  end

  describe ".union_all" do
    it "works" do
      union = User.new(id: 1).posts.union_all(Post.where("created_at > ?", Time.utc(2014, 7, 19, 0, 0, 0)))

      expect(union.to_sql.squish).to eq(
        "SELECT \"posts\".* FROM ( SELECT \"posts\".* FROM \"posts\" WHERE \"posts\".\"user_id\" = 1 UNION ALL SELECT \"posts\".* FROM \"posts\" WHERE (created_at > '2014-07-19 00:00:00.000000') ) \"posts\""
      )
      expect{union.to_a}.to_not raise_error
    end
  end
end

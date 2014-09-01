module ActiveRecord
  class Relation
    module Union
      def union(relation_or_where_arg, *args)
        other   = relation_or_where_arg if args.size == 0 && Relation === relation_or_where_arg
        other ||= @klass.where(relation_or_where_arg, *args)

        verify_union_relations!(self, other)

        # Postgres allows ORDER BY in the UNION subqueries if each subquery is surrounded by parenthesis
        # but SQLite does not allow parens around the subqueries; you will have to explicitly do `relation.reorder(nil)` in SQLite
        if Arel::Visitors::SQLite === self.visitor
          left, right = self.ast, other.ast
        else
          left, right = Arel::Nodes::Grouping.new(self.ast), Arel::Nodes::Grouping.new(other.ast)
        end

        union = Arel::Nodes::Union.new(left, right)
        from = Arel::Nodes::TableAlias.new(
          union,
          Arel::Nodes::SqlLiteral.new(@klass.arel_table.name)
        )

        relation = @klass.unscoped.from(from)
        relation.bind_values = self.bind_values + other.bind_values
        relation
      end

      private

      def verify_union_relations!(*args)
        includes_relations = args.select { |r| r.includes_values.any? }
        if includes_relations.any?
          raise ArgumentError.new("Cannot union relation with includes.")
        end

        preload_relations = args.select { |r| r.preload_values.any? }
        if preload_relations.any?
          raise ArgumentError.new("Cannot union relation with preload.")
        end

        eager_load_relations = args.select { |r| r.eager_load_values.any? }
        if eager_load_relations.any?
          raise ArgumentError.new("Cannot union relation with eager load.")
        end
      end
    end
  end
end

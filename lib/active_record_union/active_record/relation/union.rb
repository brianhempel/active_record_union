module ActiveRecord
  class Relation
    module Union

      SET_OPERATION_TO_AREL_CLASS = {
        union:     Arel::Nodes::Union,
        union_all: Arel::Nodes::UnionAll
      }

      def union(relation_or_where_arg, *args)
        set_operation(:union, relation_or_where_arg, *args)
      end

      def union_all(relation_or_where_arg, *args)
        set_operation(:union_all, relation_or_where_arg, *args)
      end

      private

      def set_operation(operation, relation_or_where_arg, *args)
        other = if args.empty? && relation_or_where_arg.is_a?(Relation)
                  relation_or_where_arg
                else
                  self.klass.where(relation_or_where_arg, *args)
                end

        verify_relations_for_set_operation!(operation, self, other)

        left = self.arel.ast
        right = other.arel.ast

        # Postgres allows ORDER BY in the UNION subqueries if each subquery is surrounded by parenthesis
        # but SQLite does not allow parens around the subqueries
        unless self.connection.visitor.is_a?(Arel::Visitors::SQLite)
          left = Arel::Nodes::Grouping.new(left)
          right = Arel::Nodes::Grouping.new(right)
        end

        set  = SET_OPERATION_TO_AREL_CLASS[operation].new(left, right)
        from = Arel::Nodes::TableAlias.new(set, self.klass.arel_table.name)
        build_union_relation(from, other)
      end

      def build_union_relation(arel_table_alias, _other)
        self.klass.unscoped.from(arel_table_alias)
      end

      def verify_relations_for_set_operation!(operation, *relations)
        includes_relations = relations.select { |r| r.includes_values.any? }

        if includes_relations.any?
          raise ArgumentError.new("Cannot #{operation} relation with includes.")
        end

        preload_relations = relations.select { |r| r.preload_values.any? }
        if preload_relations.any?
          raise ArgumentError.new("Cannot #{operation} relation with preload.")
        end

        eager_load_relations = relations.select { |r| r.eager_load_values.any? }
        if eager_load_relations.any?
          raise ArgumentError.new("Cannot #{operation} relation with eager load.")
        end
      end
    end
  end
end

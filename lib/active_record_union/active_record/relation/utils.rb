module ActiveRecord
  class Relation
    module Utils
      SET_OPERATION_TO_AREL_CLASS = {
        intersect:     Arel::Nodes::Intersect,
        union:     Arel::Nodes::Union,
        union_all: Arel::Nodes::UnionAll
      }.freeze

      def set_operation(operation, relation_or_where_arg, *args)
        other = if args.empty? && relation_or_where_arg.is_a?(Relation)
                  relation_or_where_arg
                else
                  @klass.where(relation_or_where_arg, *args)
                end

        verify_relations_for_set_operation!(operation, self, other)

        left = arel.ast
        right = other.arel.ast

        # Postgres allows ORDER BY in the UNION subqueries if each subquery is surrounded by parenthesis
        # but SQLite does not allow parens around the subqueries
        unless connection.visitor.is_a?(Arel::Visitors::SQLite)
          left = Arel::Nodes::Grouping.new(left)
          right = Arel::Nodes::Grouping.new(right)
        end

        set  = SET_OPERATION_TO_AREL_CLASS[operation].new(left, right)
        from = Arel::Nodes::TableAlias.new(set, @klass.arel_table.name)
        [from, other]
      end
    end
  end
end

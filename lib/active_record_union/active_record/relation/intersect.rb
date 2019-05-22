module ActiveRecord
  class Relation
    module Intersect
      SET_OPERATION_TO_AREL_CLASS = {
        intersect:     Arel::Nodes::Intersect
      }.freeze

      def intersect(relation_or_where_arg, *args)
        set_operation(:intersect, relation_or_where_arg, *args)
      end

      private

      def set_operation(operation, relation_or_where_arg, *args)
        other = if args.empty? && relation_or_where_arg.is_a?(Relation)
                  relation_or_where_arg
                else
                  @klass.where(relation_or_where_arg, *args)
                end

        verify_relations_for_set_operation!(operation, self, other)

        left = arel.ast
        right = other.arel.ast

        # Postgres allows ORDER BY in the INTERSECT subqueries if each subquery is surrounded by parenthesis
        # but SQLite does not allow parens around the subqueries
        unless connection.visitor.is_a?(Arel::Visitors::SQLite)
          left = Arel::Nodes::Grouping.new(left)
          right = Arel::Nodes::Grouping.new(right)
        end

        set  = SET_OPERATION_TO_AREL_CLASS[operation].new(left, right)
        from = Arel::Nodes::TableAlias.new(set, @klass.arel_table.name)
        build_intersect_relation(from, other)
      end

      if ActiveRecord.gem_version >= Gem::Version.new('5.2.0.beta2')
        # Since Rails 5.2, binds are maintained only in the Arel AST.
        def build_intersect_relation(arel_table_alias, _other)
          @klass.unscoped.from(arel_table_alias)
        end
      elsif ActiveRecord::VERSION::MAJOR >= 5
        # In Rails >= 5.0, < 5.2, binds are maintained only in ActiveRecord
        # relations and clauses.
        def build_intersect_relation(arel_table_alias, other)
          relation = @klass.unscoped.spawn
          relation.from_clause =
            IntersectFromClause.new(arel_table_alias, nil,
                                    bound_attributes + other.bound_attributes)
          relation
        end

        class IntersectFromClause < ActiveRecord::Relation::FromClause
          def initialize(value, name, bound_attributes)
            super(value, name)
            @bound_attributes = bound_attributes
          end

          def binds
            @bound_attributes
          end
        end
      else
        # In Rails 4.x, binds are maintained in both ActiveRecord relations and
        # clauses and also in their Arel ASTs.
        def build_intersect_relation(arel_table_alias, other)
          relation = @klass.unscoped.from(arel_table_alias)
          relation.bind_values = arel.bind_values + bind_values +
                                 other.arel.bind_values + other.bind_values
          relation
        end
      end

      def verify_relations_for_set_operation!(operation, *relations)
        includes_relations = relations.select { |r| r.includes_values.any? }

        if includes_relations.any?
          raise ArgumentError, "Cannot #{operation} relation with includes."
        end

        preload_relations = relations.select { |r| r.preload_values.any? }
        if preload_relations.any?
          raise ArgumentError, "Cannot #{operation} relation with preload."
        end

        eager_load_relations = relations.select { |r| r.eager_load_values.any? }
        if eager_load_relations.any?
          raise ArgumentError, "Cannot #{operation} relation with eager load."
        end
      end
    end
  end
end

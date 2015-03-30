module ActiveRecord
  class Relation
    module Union

      SET_OPERATION_TO_AREL_CLASS = {
        "UNION"     => Arel::Nodes::Union,
        "UNION ALL" => Arel::Nodes::UnionAll
      }

      def  union(relation_or_where_arg, *args)
        set_operation("UNION", relation_or_where_arg, *args)
      end

      def  union_all(relation_or_where_arg, *args)
        set_operation("UNION ALL", relation_or_where_arg, *args)
      end

      private

      def set_operation(operation, relation_or_where_arg, *args)
        other = if args.size == 0 && Relation === relation_or_where_arg
          relation_or_where_arg
        else
          @klass.where(relation_or_where_arg, *args)
        end

        verify_relations_for_set_operation!(operation, self, other)

        # Postgres allows ORDER BY in the UNION subqueries if each subquery is surrounded by parenthesis
        # but SQLite does not allow parens around the subqueries; you will have to explicitly do `relation.reorder(nil)` in SQLite
        if Arel::Visitors::SQLite === self.visitor
          left, right = self.ast, other.ast
        else
          left, right = Arel::Nodes::Grouping.new(self.ast), Arel::Nodes::Grouping.new(other.ast)
        end

        set = SET_OPERATION_TO_AREL_CLASS[operation].new(left, right)
        from = Arel::Nodes::TableAlias.new(
          set,
          Arel::Nodes::SqlLiteral.new(@klass.arel_table.name)
        )

        relation = @klass.unscoped.from(from)
        relation.bind_values = self.bind_values + other.bind_values
        relation
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

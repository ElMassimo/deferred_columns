# frozen_string_literal: true

module DeferredColumns
  # Query methods, and the default SELECT for models with deferred columns.
  module Relation
    # Carries the columns a query opted into. Stored as an extension so that it
    # survives merges and association scopes, and so that `count` still counts
    # rows instead of the selected columns.
    class OptIn < Module
      attr_reader :columns

      def initialize(columns)
        @columns = columns.freeze
        super()
      end
    end

    # Loads the given deferred columns, along with the default ones. A query
    # that selects columns explicitly loads exactly those columns instead.
    def with_deferred(*columns)
      columns = DeferredColumns.deferred_columns!(klass, columns)
      raise ArgumentError, 'with_deferred requires at least one column' if columns.empty?

      extending(OptIn.new(columns))
    end

    # Loads every column, including the deferred ones.
    def with_deferred_columns
      deferred = klass.deferred_columns
      deferred.empty? ? self : extending(OptIn.new(deferred))
    end

  private

    def build_select(arel)
      deferred = klass.deferred_columns
      return super if deferred.empty? || select_values.any?

      opted = DeferredColumns.opted_into(self) & deferred
      loaded = opted.empty? ? klass.default_select_columns : klass.column_names - (deferred - opted)
      arel.project(*loaded.map { |column| table[column] })
    end

    # Passes the opt-ins to the root of `eager_load`, which selects its columns.
    def construct_join_dependency(...)
      super.tap { |dependency| dependency.send(:join_root).deferred_columns_opted_into = DeferredColumns.opted_into(self) }
    end
  end

  # The deferred columns a query opted into.
  def self.opted_into(relation)
    relation.extending_values.grep(Relation::OptIn).flat_map(&:columns).uniq
  end
end

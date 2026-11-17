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
      columns = columns.flatten.map(&:to_s)
      raise ArgumentError, 'with_deferred requires at least one column' if columns.empty?

      unknown = columns - klass.deferred_columns
      if unknown.any?
        raise ArgumentError, "#{unknown.join(', ')} #{unknown.one? ? 'is not a deferred column' : 'are not deferred columns'} of #{klass.name}"
      end

      extending(OptIn.new(columns))
    end

    # Loads every column, including the deferred ones.
    def select_all_columns
      deferred = klass.deferred_columns
      deferred.empty? ? self : extending(OptIn.new(deferred))
    end
    alias with_deferred_columns select_all_columns

  private

    def build_select(arel)
      deferred = klass.deferred_columns
      return super if deferred.empty? || select_values.any?

      opted = deferred_columns_opted_into & deferred
      loaded = opted.empty? ? klass.default_select_columns : klass.column_names - (deferred - opted)
      arel.project(*loaded.map { |column| table[column] })
    end

    def deferred_columns_opted_into
      extending_values.grep(OptIn).flat_map(&:columns).uniq
    end
  end
end

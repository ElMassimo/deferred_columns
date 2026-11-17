# frozen_string_literal: true

module DeferredColumns
  # `eager_load` builds its SELECT from the column names of each joined model,
  # without going through Relation#build_select.
  module JoinPart
    def column_names
      base_klass.deferred_columns.empty? ? super : base_klass.default_select_columns
    end
  end
end

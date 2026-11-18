# frozen_string_literal: true

module DeferredColumns
  # `eager_load` builds its SELECT from the column names of each joined model,
  # without going through Relation#build_select.
  module JoinPart
    # Opt-ins of the query, for the root model.
    attr_writer :deferred_columns_opted_into

    def column_names
      deferred = base_klass.deferred_columns
      return super if deferred.empty?

      opted = deferred_columns_opted_into & deferred
      opted.empty? ? base_klass.default_select_columns : base_klass.column_names - (deferred - opted)
    end

  private

    # Opt-ins of the association scope, for joined models.
    def deferred_columns_opted_into
      @deferred_columns_opted_into ||=
        if is_a?(ActiveRecord::Associations::JoinDependency::JoinAssociation) && reflection.scope
          DeferredColumns.opted_into(reflection.scope_for(base_klass.unscoped))
        else
          []
        end
    end
  end
end

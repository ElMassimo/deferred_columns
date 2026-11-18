# frozen_string_literal: true

module DeferredColumns
  # Preloading skips associations that are already loaded, so the deferred
  # columns its scope opts into would never reach their records.
  module Preloader
    def run
      load_opted_into_loaded_targets unless run?
      super
    end

  private

    def load_opted_into_loaded_targets
      opted = DeferredColumns.opted_into(reflection_scope)
      opted |= DeferredColumns.opted_into(preload_scope) if preload_scope
      return if opted.empty?

      records = owners.select { |owner| loaded?(owner) }.flat_map { |owner| target_for(owner) }
      unloaded = records.select { |record| opted.any? { |column| DeferredColumns.unloaded?(record, column) } }
      return if unloaded.empty?

      model = unloaded.first.class
      column = opted.find { |name| DeferredColumns.unloaded?(unloaded.first, name) }
      message = "#{owners.first.class.name}##{reflection.name} was already loaded without #{model.name}##{column}, " \
                'so preloading it again with that deferred column skipped it. ' \
                "Opt into it where the association is first loaded, for example: #{model.name}.with_deferred(:#{column})"
      DeferredColumns.not_loaded!(unloaded, NotLoadedError.new(model, column, message), opted)
    end
  end
end

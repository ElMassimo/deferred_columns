# frozen_string_literal: true

module DeferredColumns
  # A deferred column that wasn't loaded can't have changed, so validators skip
  # it instead of raising, or reading it as nil.
  module Validator
    def validate(record)
      unloaded = attributes.select { |attribute| DeferredColumns.unloaded?(record, attribute) }
      return super if unloaded.empty?

      loaded = attributes - unloaded
      return if loaded.empty?

      dup.tap { |validator| validator.instance_variable_set(:@attributes, loaded) }.validate(record)
    end
  end
end

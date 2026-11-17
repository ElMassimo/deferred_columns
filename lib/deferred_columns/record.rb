# frozen_string_literal: true

module DeferredColumns
  # Instance methods available in every Active Record model.
  module Record
    # Loads deferred columns into a record that was loaded without them, in a
    # single query. Without arguments, loads every deferred column it lacks.
    #
    # Prefer `with_deferred` in the query that loads the records; this is for
    # records loaded elsewhere, such as job arguments or `self` in a callback.
    def load_deferred(*columns)
      columns = DeferredColumns.deferred_columns!(self.class, columns)
      columns = self.class.deferred_columns if columns.empty?
      missing = columns.reject { |column| has_attribute?(column) }
      return self if missing.empty? || new_record?

      row = self.class.unscoped.where(self.class.primary_key => id_in_database).select(*missing).take!
      missing.each { |column| @attributes.write_from_database(column, row.read_attribute_before_type_cast(column)) }
      self
    end

    # Reloads the record, keeping the deferred columns it had loaded.
    def reload(*)
      loaded = self.class.deferred_columns.select { |column| has_attribute?(column) }
      super.tap { load_deferred(*loaded) if loaded.any? }
    end
  end
end

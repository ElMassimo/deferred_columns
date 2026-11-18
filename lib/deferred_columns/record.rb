# frozen_string_literal: true

module DeferredColumns
  # Instance methods available in every Active Record model.
  module Record
    # Loads deferred columns or groups into a record that was loaded without
    # them, in a single query. Without arguments, loads every deferred column.
    #
    # Prefer `with_deferred` in the query that loads the records; this is for
    # records loaded elsewhere, such as job arguments or `self` in a callback.
    def load_deferred(*names)
      DeferredColumns.load(self, *names)
      self
    end

    # Raises instead of returning nil for deferred columns that weren't loaded,
    # which also applies to `record[column]`.
    def read_attribute(name, &)
      if self.class.deferred_columns.any?
        column = name.to_s
        column = self.class.attribute_aliases.fetch(column, column)
        DeferredColumns.not_loaded!(self, NotLoadedError.new(self.class, column)) if DeferredColumns.unloaded?(self, column)
      end

      super
    end

    # Reloads the record, keeping the deferred columns it had loaded.
    def reload(*)
      loaded = self.class.deferred_columns.select { |column| has_attribute?(column) }
      super.tap { load_deferred(*loaded) if loaded.any? }
    end

  private

    def load_deferred_column(column, value)
      @attributes.write_from_database(column, value) unless has_attribute?(column)
    end
  end

  # Loads deferred columns or groups into records that were loaded without them,
  # with one query per model. Without names, loads every deferred column.
  #
  # Records that already have a column keep their value, and new records are
  # skipped, so it only queries for what's missing.
  def self.load(records, *names)
    records = Array(records)
    records.group_by(&:class).each do |model, siblings|
      columns = deferred_columns!(model, names)
      columns = model.deferred_columns if columns.empty?
      persisted = siblings.reject(&:new_record?)
      missing = columns.reject { |column| persisted.all? { |record| record.has_attribute?(column) } }
      next if missing.empty?

      primary_key = model.primary_key
      query = model.unscoped.where(primary_key => persisted.map(&:id_in_database)).select(primary_key, *missing)
      # Reads raw values, which the records cast when read, without instantiating
      # a record per row or running its callbacks.
      rows = model.with_connection { |connection| connection.select_rows(query.arel, "#{model.name} Load Deferred") }
      key_type = model.type_for_attribute(primary_key)
      rows = rows.index_by { |row| key_type.deserialize(row.first) }
      persisted.each do |record|
        row = rows.fetch(record.id_in_database) { raise ActiveRecord::RecordNotFound.new("Couldn't find #{model.name} with '#{primary_key}'=#{record.id_in_database}", model.name, primary_key) }
        missing.each.with_index(1) { |column, index| record.send(:load_deferred_column, column, row[index]) }
      end
    end
    records
  end
end

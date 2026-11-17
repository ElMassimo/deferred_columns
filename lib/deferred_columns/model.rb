# frozen_string_literal: true

module DeferredColumns
  # Class methods available in every Active Record model.
  module Model
    def self.extended(base)
      base.class_attribute :deferred_columns, instance_accessor: false, default: [].freeze
      base.class_attribute :deferred_column_groups, instance_accessor: false, default: {}.freeze
    end

    # Leaves the given columns out of the default SELECT.
    #
    # Reading one of them on a record that was loaded without it raises
    # DeferredColumns::NotLoadedError, instead of running a query per record.
    #
    # Pass `as:` to name the group of columns, so that queries can opt into all
    # of them with `with_deferred(:name)`.
    def defer_columns(*columns, as: nil)
      columns = columns.flatten.map(&:to_s)
      clashing = columns & deferred_column_groups.keys
      raise ArgumentError, "#{clashing.join(', ')} already names a group of deferred columns in #{name}" if clashing.any?

      self.deferred_columns = (deferred_columns | columns).freeze
      add_deferred_column_group(as.to_s, columns) if as

      columns.each do |column|
        deferred_column_readers.define_method(column) do
          raise NotLoadedError.new(self.class, column) unless has_attribute?(column)

          super()
        end
      end
    end

    # Loads the given deferred columns, along with the default ones.
    def with_deferred(*columns)
      all.with_deferred(*columns)
    end

    # Loads every column, including the deferred ones.
    def with_deferred_columns
      all.with_deferred_columns
    end

    # The columns loaded by a query that doesn't select any explicitly.
    def default_select_columns
      deferred = deferred_columns
      columns = column_names
      cached = @default_select_columns
      return cached[2] if cached && cached[0].equal?(deferred) && cached[1].equal?(columns)

      (@default_select_columns = [deferred, columns, (columns - deferred).freeze])[2]
    end

  private

    def add_deferred_column_group(group, columns)
      raise ArgumentError, "#{group} is a deferred column of #{name}, so it can't name a group" if deferred_columns.include?(group)

      grouped = (deferred_column_groups.fetch(group, []) | columns).freeze
      self.deferred_column_groups = deferred_column_groups.merge(group => grouped).freeze
    end

    def deferred_column_readers
      @deferred_column_readers ||= Module.new.tap { |readers| include readers }
    end
  end
end

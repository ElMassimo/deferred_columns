# frozen_string_literal: true

require 'active_record'
require 'deferred_columns/version'

# Leaves heavy columns out of the default SELECT of an Active Record model, and
# lets each query opt into them.
#
#   class Song < ActiveRecord::Base
#     defer_columns :lyrics
#   end
#
#   Song.where(album: abraxas)            # every column but lyrics
#   Song.with_deferred(:lyrics).first     # plus lyrics, in the same query
#   Song.first.lyrics                     # raises DeferredColumns::NotLoadedError
module DeferredColumns
  # Raised when reading a deferred column that the query didn't select.
  class NotLoadedError < ActiveModel::MissingAttributeError
    attr_reader :model, :column

    def initialize(model, column)
      @model = model
      @column = column
      name = model.deferred_column_groups.find { |_group, columns| columns.include?(column) }&.first || column
      super(
        "#{model.name}##{column} is a deferred column, so it isn't loaded by default. " \
        "Select it in the query, for example: #{model.name}.with_deferred(:#{name}), " \
        "or load it into the record with load_deferred(:#{name})",
      )
    end
  end

  # The columns for the given names of deferred columns or groups, as long as
  # all of them are deferred in the model.
  def self.deferred_columns!(model, names)
    groups = model.deferred_column_groups
    columns = names.flatten.flat_map { |name| groups.fetch(name.to_s) { [name.to_s] } }.uniq
    unknown = columns - model.deferred_columns
    return columns if unknown.empty?

    raise ArgumentError, "#{unknown.join(', ')} #{unknown.one? ? 'is not a deferred column or group' : 'are not deferred columns or groups'} of #{model.name}"
  end

  # Whether the record was loaded without the given deferred column.
  def self.unloaded?(record, column)
    model = record.class
    model.respond_to?(:deferred_columns) &&
      model.deferred_columns.include?(column.to_s) &&
      !record.has_attribute?(column)
  end
end

require 'deferred_columns/model'
require 'deferred_columns/record'
require 'deferred_columns/relation'
require 'deferred_columns/join_part'
require 'deferred_columns/validator'

ActiveSupport.on_load(:active_record) do
  extend DeferredColumns::Model
  include DeferredColumns::Record
  ActiveRecord::Relation.prepend(DeferredColumns::Relation)

  require 'active_record/associations/join_dependency/join_part'
  ActiveRecord::Associations::JoinDependency::JoinPart.prepend(DeferredColumns::JoinPart)
end

ActiveModel::EachValidator.prepend(DeferredColumns::Validator)

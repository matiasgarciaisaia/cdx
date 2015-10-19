class Case < ActiveRecord::Base

  include AutoUUID

  belongs_to :source, polymorphic: true

  validates :source, presence: true

  scope :sources, ->(sources) {
    return none if sources.blank?
    arel = sources.group_by{|s| s.class.name}.inject(nil) do |filters, type_with_ids|
      type, ids = type_with_ids
      filter = Case.arel_table[:source_type].eq(type).and(Case.arel_table[:source_id].in(ids))
      filters ? filters.or(filter) : filter
    end
    where(arel)
  }

end

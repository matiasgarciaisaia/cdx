class Case < ActiveRecord::Base

  include AutoUUID

  belongs_to :source, polymorphic: true

  validates :source, presence: true

end

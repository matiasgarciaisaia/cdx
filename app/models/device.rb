class Device < ActiveRecord::Base
  belongs_to :device_model
  belongs_to :institution
  has_and_belongs_to_many :laboratories
  has_many :events

  validates_presence_of :institution
  validates_presence_of :name

  before_create :set_key

  def self.filter_by_owner(user)
    joins(:institution).where(institutions: {user_id: user.id})
  end

  def filter_by_owner(user)
    institution.user_id == user.id ? self : nil
  end

  def to_s
    name
  end

  private

  def set_key
    self.secret_key = Guid.new.to_s
  end
end

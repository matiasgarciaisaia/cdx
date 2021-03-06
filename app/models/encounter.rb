class Encounter < ActiveRecord::Base
  include Entity
  include AutoUUID
  include Resource

  ASSAYS_FIELD = 'diagnosis'
  OBSERVATIONS_FIELD = 'observations'

  has_many :samples, dependent: :restrict_with_error
  has_many :test_results, dependent: :restrict_with_error

  belongs_to :institution
  belongs_to :site
  belongs_to :patient

  validates_presence_of :institution
  validates_presence_of :site, if: Proc.new { |encounter| encounter.institution && !encounter.institution.kind_manufacturer? }
  validate :same_institution_of_site

  validate :validate_patient

  before_save :ensure_entity_id

  attr_accessor :new_samples # Array({entity_id: String}) of new generated samples from UI.

  def entity_id
    core_fields["id"]
  end

  def has_entity_id?
    entity_id.not_nil?
  end

  def phantom?
    super && core_fields[ASSAYS_FIELD].blank? && plain_sensitive_data[OBSERVATIONS_FIELD].blank?
  end

  def self.merge_assays(assays1, assays2)
    return assays2 unless assays1
    return assays1 unless assays2

    assays1.dup.tap do |res|
      assays2.each do |assay2|
        assay = res.find { |a| a["condition"] == assay2["condition"] }
        if assay.nil?
          res << assay2.dup
        else
          assay.merge! assay2 do |key, v1, v2|
            if key == "result"
              values = []
              values << v1 if v1 && v1 != "n/a"
              values << v2 if v2 && v2 != "n/a"
              values << "indeterminate" if values.empty?
              values.uniq!
              if values.length == 1
                values.first
              else
                "indeterminate"
              end
            else
              v1
            end
          end
        end
      end
    end
  end

  def self.merge_assays_without_values(assays1, assays2)
    return assays2 unless assays1
    return assays1 unless assays2

    assays1.dup.tap do |res|
      assays2.each do |assay2|
        assay = res.find { |a| a["condition"] == assay2["condition"] }
        if assay.nil?
          res << (assay2.dup.tap do |h|
            h["result"] = nil
          end)
        end
      end
    end
  end

  def self.entity_scope
    "encounter"
  end

  def self.find_by_entity_id(entity_id, opts)
    find_by(entity_id: entity_id.to_s, institution_id: opts.fetch(:institution_id))
  end

  def self.query params, user
    EncounterQuery.for params, user
  end

  def test_results_not_in_diagnostic
    test_results.where("updated_at > ?", self.user_updated_at || self.created_at)
  end

  def has_dirty_diagnostic?
    test_results_not_in_diagnostic.count > 0
  end

  def updated_diagnostic
    assays_to_merge = test_results_not_in_diagnostic\
      .map{|tr| tr.core_fields[TestResult::ASSAYS_FIELD]}

    assays_to_merge.inject(core_fields[Encounter::ASSAYS_FIELD]) do |merged, to_merge|
      Encounter.merge_assays_without_values(merged, to_merge)
    end
  end

  def updated_diagnostic_timestamp!
    update_attribute(:user_updated_at, Time.now.utc)
  end

  protected

  def ensure_entity_id
    self.entity_id = entity_id
  end

  def same_institution_of_site
    if self.site && self.site.institution != self.institution
      errors.add(:site, "must belong to the institution of the device")
    end
  end

end

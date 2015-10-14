class TestResultIndexer < EntityIndexer

  alias_method :test_result, :entity

  def index(refresh = false)
    super
    percolate
  end

  def percolate
    percolate_result = client.percolate index: Cdx::Api.index_name, type: type, id: test_result.uuid
    percolate_result["matches"].each do |match|
      subscriber_id = match["_id"]
      NotifySubscriberJob.perform_later subscriber_id, test_result.uuid
    end
  end

  def type
    'test'
  end

  def fields_to_index
    site = device.site
    site_uuid = site.try &:uuid
    site_name = site.try &:name

    location = site.try &:location
    location_id = location.try(:geo_id)
    location_lat = location.try(:lat)
    location_lng = location.try(:lng)

    parent_locations = location.try(:self_and_ancestors) || []
    parent_locations_id = parent_locations.map(&:geo_id)
    admin_levels = Hash[parent_locations.map { |l| ["admin_level_#{l.admin_level}", l.geo_id] }]

    {test_result.entity_scope => test_result.core_fields}.
      deep_merge({
        "test" => {
          "reported_time" => test_result.created_at.utc.iso8601,
          "updated_time" => test_result.updated_at.utc.iso8601,
          "uuid" => test_result.uuid
        },
        "device" => {
          "uuid" => device.uuid,
          "model" => device.device_model.name,
          "serial_number" => device.serial_number
        },
        "location" => {
          "id" => location_id,
          "parents" => parent_locations_id,
          "admin_levels" => admin_levels,
          "lat" => location_lat,
          "lng" => location_lng
        },
        "institution" => {
          "uuid" => device.institution.uuid
        },
        "site" => {
          "uuid" => site_uuid
        }
      }).
      deep_merge(core_fields_from(test_result.sample)).
      deep_merge(core_fields_from(test_result.encounter)).
      deep_merge(core_fields_from(test_result.patient)).
      deep_merge(all_custom_fields)
  end

  def device
    test_result.device
  end

  def all_custom_fields
    [test_result, test_result.sample, test_result.encounter, test_result.patient].inject(Hash.new) do |fields, entity|
      append_custom_fields fields, entity
    end
  end

end

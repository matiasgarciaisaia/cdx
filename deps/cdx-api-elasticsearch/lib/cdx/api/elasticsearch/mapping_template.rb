class Cdx::Api::Elasticsearch::MappingTemplate

  def initialize(api = Cdx::Api)
    @api = api
  end

  def initialize_template(template_name)
    @api.client.indices.put_template name: template_name, body: template
  end

  def template
    {
      template: template_name,
      mappings: {
        test: test_mapping,
        encounter: encounter_mapping
      }
    }
  end

  def template_name
    @api.config.template_name_pattern
  end

  def encounter_mapping
    {
      dynamic_templates: build_dynamic_templates,
      properties: build_properties_mapping_from(%W(encounter patient institution))
    }
  end

  def test_mapping
    {
      dynamic_templates: build_dynamic_templates,
      properties: build_properties_mapping_from(Cdx.core_field_scopes.map(&:name))
    }
  end

  def build_dynamic_templates
    [
      {
        "admin_levels" => {
          path_match: "*.admin_level_*",
          mapping: { type: :string, index: :not_analyzed }
        }
      },
      {
        "custom_fields" => {
          path_match: "*.custom_fields.*",
          mapping: { enabled: false }
        }
      }
    ]
  end

  def build_properties_mapping_from(scopes)
    scoped_fields = Cdx.core_field_scopes.select{|s| s.searchable? && scopes.include?(s.name)}

    Hash[
      scoped_fields.map { |scope|
        [ scope.name.to_s, scope.elasticsearch_mapping ]
      }
    ]
  end
end

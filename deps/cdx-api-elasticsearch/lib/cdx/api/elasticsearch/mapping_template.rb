class Cdx::Api::Elasticsearch::MappingTemplate

  def initialize(api = Cdx::Api)
    @api = api
  end

  def initialize_template(template_name)
    @api.client.indices.put_template name: template_name, body: template
  end

  def template
    {
      template: @api.config.template_name_pattern,
      mappings: {
        test: test_mapping,
        encounter: encounter_mapping
      }
    }
  end

  def encounter_mapping
    Cdx.core_field_scopes.find{|s| s.name == 'encounter'}.elasticsearch_mapping
  end

  def test_mapping
    {
      dynamic_templates: build_test_dynamic_templates,
      properties: build_test_properties_mapping
    }
  end

  def build_test_dynamic_templates
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

  def build_test_properties_mapping
    scoped_fields = Cdx.core_field_scopes.select(&:searchable?)

    Hash[
      scoped_fields.map { |scope|
        [ scope.name, scope.elasticsearch_mapping ]
      }
    ]
  end
end

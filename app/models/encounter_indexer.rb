class EncounterIndexer < EntityIndexer

  alias_method :encounter, :entity

  def type
    'encounter'
  end

  def client
    Cdx::Api.client
  end

  def fields_to_index
    {encounter.entity_scope => encounter.core_fields}.
      deep_merge({
        "institution" => {
          "uuid" => encounter.institution.uuid
        },
        "encounter" => {
          "uuid" => encounter.uuid
        },
      }).
      deep_merge(core_fields_from(encounter.patient)).
      deep_merge(all_custom_fields)
  end

  def all_custom_fields
    fields = {}
    append_custom_fields fields, encounter
    append_custom_fields fields, encounter.patient

    fields
  end

end

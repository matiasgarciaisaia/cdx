class EntityIndexer
  attr_reader :entity, :fields

  def initialize entity
    @entity = entity
  end

  def index(refresh = false)
    fields = fields_to_index
    run_before_index_hooks(fields)
    options = {index: Cdx::Api.index_name, type: type, body: fields, id: entity.uuid}
    options[:refresh] = true if refresh
    client.index(options)
  end

  def run_before_index_hooks(fields)
    Cdx.core_field_scopes.each do |scope|
      scope.fields.each do |field|
        field.before_index fields
      end
    end
  end

  def destroy
    client.delete(index: Cdx::Api.index_name, type: type, id: entity.uuid)
  end

  def type
    subclass_responsibility
  end

  def fields_to_index
    subclass_responsibility
  end

  def client
    Cdx::Api.client
  end

  protected

  def core_fields_from entity
    if entity && !entity.empty_entity?
      {entity.entity_scope => entity.core_fields.deep_merge("uuid" => entity.uuid)}
    else
      {}
    end
  end

  def append_custom_fields fields, entity
    if entity && entity.custom_fields.present?
      fields[entity.entity_scope] ||= { "custom_fields" => {} }
      fields[entity.entity_scope]["custom_fields"].deep_merge! entity.custom_fields
    end
    fields
  end

end

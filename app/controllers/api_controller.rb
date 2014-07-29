class ApiController < ApplicationController
  include ApplicationHelper
  include Policy::Actions

  skip_before_filter :verify_authenticity_token
  skip_before_action :authenticate_user!
  before_action :authenticate_api_user!

  def create
    device = Device.includes(:manifests).includes(:institution).includes(:laboratories).includes(:locations).find_by_secret_key(params[:device_uuid])
    Event.create_or_update_with device, request.body.read
    head :ok
  end

  def events
    body = Oj.load(request.body.read) || {}
    result = Cdx::Api::Elasticsearch::Query.new(params.merge(body)).execute
    render_json result
  end

  def custom_fields
    event = Event.find_by_uuid(params[:event_uuid])
    render_json "uuid" => params[:event_uuid], "custom_fields" => event.custom_fields
  end

  def pii
    event = Event.find_by_uuid(params[:event_uuid])
    render_json "uuid" => params[:event_uuid], "pii" => event.decrypt.sensitive_data
  end

  def playground
    @devices = Device.all
  end
end

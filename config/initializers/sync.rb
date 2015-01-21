require 'cdx_sync'

CDXSync.instance_eval do

  def default_sync_dir_path
    Rails.application.config.sync_dir_path
  end

  def default_authorized_keys_path
    Rails.application.config.authorized_keys_path
  end

  def rrsync_location
    '/usr/local/bin/rrsync'
  end
end

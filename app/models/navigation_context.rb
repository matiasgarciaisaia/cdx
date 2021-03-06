class NavigationContext
  attr_reader :user

  attr_reader :institution
  attr_reader :site

  def initialize(user = nil, uuid = nil)
    @user = user

    @institution = Institution.where(uuid: uuid).first
    @site = nil

    unless @institution
      @site = Site.where(uuid: uuid).first
      @institution = @site.try :institution
    end
  end

  def can_read?
    if @site
      Policy.can?(Policy::Actions::READ_SITE, @site, @user)
    elsif @institution
      Policy.can?(Policy::Actions::READ_INSTITUTION, @institution, @user)
    else
      false
    end
  end

  def entity
    site || institution
  end

  def name
    entity.try :name
  end

  def uuid
    entity.try :uuid
  end

  def to_hash
    Hash.new.tap do |h|
      if entity
        h[:name] = name  
        h[:uuid] = uuid
      end
      h[:institution] = { name: institution.name, uuid: institution.uuid } if institution
      h[:site] = { name: site.name, uuid: site.uuid } if site
    end
  end
end

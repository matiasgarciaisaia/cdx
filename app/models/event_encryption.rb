module EventEncryption
  def self.encrypt string
    Encryptor.encrypt string, :key => secret_key, :iv => iv, :salt => salt
  end

  def self.decrypt string
    Encryptor.decrypt(string, :key => secret_key, :iv => iv, :salt => salt)
  end

  private

  def self.secret_key
    ENV['EVENT_SECRET_KEY'] || Devise.secret_key
  end

  def self.iv
    # OpenSSL::Cipher::Cipher.new('aes-256-cbc').random_iv
    ENV['EVENT_IV'] || "\xD7\xCA\xD5\x9D\x1D\xC0I\x01Sf\xC8\xFBa\x88\xE1\x03"
  end

  def self.salt
    # Time.now.to_i.to_s
    ENV['EVENT_SALT'] || "1403203711"
  end
end

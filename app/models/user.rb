class User < ActiveRecord::Base
  acts_as_paranoid # soft delete
  has_paper_trail
  
  has_many   :roles, dependent: :destroy
  belongs_to :current_provider, class_name: "Provider", foreign_key: :current_provider_id
  has_one    :driver
  has_one    :device_pool_driver, through: :driver
  
  # Include default devise modules. Others available are:
  # :rememberable, :token_authenticatable, :confirmable, :lockable
  devise :database_authenticatable, :recoverable, :trackable, :validatable, 
    :timeoutable, :password_expirable, :password_archivable, :account_expireable

  # Let Devise handle the email format requirement
  validates :email, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  
  # Let Devise handle the password length requirement
  validates :password, confirmation: true, format: {
    if: :password_required?,
    with: /\A(?=.*[0-9])(?=.*[A-Z])(.*)\z/,
    message: "must have at least one number and at least one capital letter"
  }
  
  before_validation do
    self.email = self.email.downcase if self.email.present?
  end
  
  def self.drivers(provider)
    Driver.where(:provider_id => provider.id).map(&:user)
  end
  
  # Generate a password that will validate properly for User
  def self.generate_password(length = 8)
    # Filter commonly confused characters
    charset = (('a'..'z').to_a + ('A'..'Z').to_a) - %w(i I l o O)
    result = (1..length).collect{|a| charset[rand(charset.size)]}.join
    # Pick two indices to replace with number and symbol
    indices = (0..length-1).to_a
    n = indices.sample
    m = (indices - [n]).sample
    # At least one number
    result[n] = '23456789'.chars.to_a.sample
    # At least one capital character
    result[m] = ('A'..'Z').to_a.sample
    return result
  end

  def update_password(params)
    unless params[:password].blank?
      self.update_with_password(params)
    else
      self.errors.add('password', :blank)
      false
    end
  end

  def update_email(params)
    unless params[:email].blank?
      self.email = params[:email]
      self.save
    else
      self.errors.add('email', :blank)
      false
    end
  end
  
  # super admin (aka system admin) is regardless of providers
  def super_admin?
    !roles.system_admins.empty?
  end

  def admin?
    super_admin? || roles.where(:provider_id => current_provider.id).first.try(:admin?)
  end
  
  def editor?
    super_admin? || roles.where(:provider_id => current_provider.id).first.try(:editor?)
  end
end

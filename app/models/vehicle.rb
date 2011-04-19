class Vehicle < ActiveRecord::Base
  belongs_to :provider
  has_many :vehicle_maintenance_events

  default_scope :order => 'active, name'
  named_scope :active, :conditions => { :active => true }

  validates_length_of :vin, :is=>17
  validates_format_of :vin, :with => /^[^ioq]*$/i
end

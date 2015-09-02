class Trip < ActiveRecord::Base
  include RequiredFieldValidatorModule
  include RecurringRideCoordinator

  has_paper_trail
  
  attr_accessor :driver_id, :vehicle_id, :via_repeating_trip

  belongs_to :called_back_by, class_name: "User"
  belongs_to :customer
  belongs_to :dropoff_address, class_name: "Address"
  belongs_to :funding_source
  belongs_to :mobility
  belongs_to :pickup_address, class_name: "Address"
  belongs_to :provider
  belongs_to :repeating_trip
  belongs_to :run
  belongs_to :service_level
  belongs_to :trip_purpose
  belongs_to :trip_result

  delegate :label, to: :run, prefix: :run, allow_nil: true
  delegate :name, to: :customer, prefix: :customer, allow_nil: true
  delegate :name, to: :trip_purpose, prefix: :trip_purpose, allow_nil: true
  delegate :code, :name, to: :trip_result, prefix: :trip_result, allow_nil: true
  delegate :name, to: :service_level, prefix: :service_level, allow_nil: true

  before_validation :compute_run
  before_create     :create_repeating_trip
  before_update     :update_repeating_trip
  after_save        :instantiate_repeating_trips
  
  serialize :guests

  validates :appointment_time, presence: {unless: :allow_addressless_trip?}
  validates :attendant_count, numericality: {greater_than_or_equal_to: 0}
  validates :customer, associated: true
  validates :customer, presence: true
  validates :dropoff_address, associated: true, presence: {unless: :allow_addressless_trip?}
  validates :guest_count, numericality: {greater_than_or_equal_to: 0}
  validates :mileage, numericality: {greater_than: 0, allow_blank: true}
  validates :pickup_address, associated: true, presence: {unless: :allow_addressless_trip?}
  validates :pickup_time, presence: {unless: :allow_addressless_trip?}
  validates :trip_purpose_id, presence: true
  validates_datetime :appointment_time, unless: :allow_addressless_trip?
  validates_datetime :pickup_time, unless: :allow_addressless_trip?
  validate :driver_is_valid_for_vehicle
  validate :vehicle_has_open_seating_capacity

  accepts_nested_attributes_for :customer

  scope :for_cab,            -> { where(cab: true) }
  scope :not_for_cab,        -> { where(cab: false) }
  scope :for_provider,       -> (provider_id) { where(provider_id: provider_id) }
  scope :for_date,           -> (date) { where('trips.pickup_time >= ? AND trips.pickup_time < ?', date.to_datetime.in_time_zone.utc, date.to_datetime.in_time_zone.utc + 1.day) }
  scope :for_date_range,     -> (start_date, end_date) { where('trips.pickup_time >= ? AND trips.pickup_time < ?', start_date.to_datetime.in_time_zone.utc, end_date.to_datetime.in_time_zone.utc) }
  scope :for_driver,         -> (driver_id) { not_for_cab.where(runs: {driver_id: driver_id}).joins(:run) }
  scope :for_vehicle,        -> (vehicle_id) { not_for_cab.where(runs: {vehicle_id: vehicle_id}).joins(:run) }
  scope :by_result,          -> (code) { includes(:trip_result).references(:trip_result).where("trip_results.code = ?", code) }
  scope :by_funding_source,  -> (name) { includes(:funding_source).references(:funding_source).where("funding_sources.name = ?", name) }
  scope :by_trip_purpose,    -> (name) { includes(:trip_purpose).references(:trip_purpose).where("trip_purposes.name = ?", name) }
  scope :scheduled,          -> { includes(:trip_result).references(:trip_result).where("trips.trip_result_id is NULL or trip_results.code = 'COMP'") }
  scope :completed,          -> { Trip.by_result('COMP') }
  scope :turned_down,        -> { Trip.by_result('TD') }
  scope :by_service_level,   -> (level) { includes(:service_level).references(:service_level).where("service_levels.name = ?", level) }
  scope :today_and_prior,    -> { where('CAST(trips.pickup_time AS date) <= ?', Date.today.in_time_zone.utc) }
  scope :after_today,        -> { where('CAST(trips.pickup_time AS date) > ?', Date.today.in_time_zone.utc) }
  scope :prior_to,           -> (pickup_time) { where('trips.pickup_time < ?', pickup_time.to_datetime.in_time_zone.utc) }
  scope :after,              -> (pickup_time) { where('trips.pickup_time > ?', pickup_time.utc) }
  scope :repeating_based_on, -> (repeating_trip) { where(repeating_trip_id: repeating_trip.id) }
  scope :called_back,        -> { where('called_back_at IS NOT NULL') }
  scope :not_called_back,    -> { where('called_back_at IS NULL') }
  scope :individual,         -> { joins(:customer).where(customers: {group: false}) }
  scope :has_scheduled_time, -> { where.not(pickup_time: nil).where.not(appointment_time: nil) }
  scope :incomplete,         -> { where(trip_result: nil) }
  scope :during,             -> (pickup_time, appointment_time) { where('NOT ((trips.pickup_time < ? AND trips.appointment_time < ?) OR (trips.pickup_time > ? AND trips.appointment_time > ?))', pickup_time.utc, appointment_time.utc, pickup_time.utc, appointment_time.utc) }

  def date
    pickup_time.to_date
  end

  def complete
    trip_result.try(:code) == 'COMP'
  end

  def pending
    trip_result.blank?
  end

  def vehicle_id
    run ? run.vehicle_id : @vehicle_id
  end

  def driver_id
    @driver_id || run.try(:driver_id)
  end
  
  def pickup_time=(datetime)
    write_attribute :pickup_time, format_datetime(datetime)
  end
  
  def appointment_time=(datetime)
    write_attribute :appointment_time, format_datetime(datetime)
  end

  def run_text
    if cab
      "Cab"
    elsif run
      run.label
    else
      "(No run specified)"
    end
  end
  
  def trip_size
    if customer.group
      group_size
    else 
      guest_count + attendant_count + 1
    end
  end

  def trip_count
    round_trip ? trip_size * 2 : trip_size
  end

  def is_in_district?
    pickup_address.try(:in_district) && dropoff_address.try(:in_district)
  end
  
  def allow_addressless_trip?
    # The provider_id is assigned via the customer. If the customer isn't 
    # present, then the whole trip is invalid. So in that case, ignore the 
    # address errors until there is a customer.
    (customer.blank? || customer.id.blank? || (provider.present? && provider.allow_trip_entry_from_runs_page)) && run.present?
  end

  def adjusted_run_id
    cab ? Run::CAB_RUN_ID : (run_id ? run_id : Run::UNSCHEDULED_RUN_ID)
  end

  def as_calendar_json
    {
      id: id,
      start: pickup_time.iso8601,
      end: appointment_time.iso8601,
      title: customer_name + "\n" + pickup_address.try(:address_text).to_s,
      resource: pickup_time.to_date.to_s(:js)
    }
  end
  
  def as_run_event_json
    {
      id: id,
      start: pickup_time.iso8601,
      end: appointment_time.iso8601,
      title: customer_name + "\n" + pickup_address.try(:address_text).to_s,
      resource: adjusted_run_id
    }
  end
    
  private
  
  def create_repeating_trip
    if is_repeating_trip? && !via_repeating_trip
      self.repeating_trip = RepeatingTrip.create!(repeating_trip_attributes)
    end
  end

  def update_repeating_trip
    if is_repeating_trip? 
      #this is a repeating trip, so we need to edit both
      #the repeating trip, and the instance for today
      if repeating_trip.blank?
        create_repeating_trip
      else
        repeating_trip.attributes = repeating_trip_attributes
        if repeating_trip.changed?
          repeating_trip.save!
          destroy_future_repeating_trips
        end
      end
    elsif !is_repeating_trip? && repeating_trip.present?
      destroy_future_repeating_trips
      unlink_past_trips
      rt = repeating_trip
      self.repeating_trip_id = nil
      rt.destroy
    end
  end

  def instantiate_repeating_trips
    repeating_trip.instantiate! if !repeating_trip_id.nil? && !via_repeating_trip
  end

  def destroy_future_repeating_trips
    if pickup_time < Time.now #Be sure not delete trips that have already happened.
      Trip.repeating_based_on(repeating_trip).after_today.not_called_back.destroy_all
    else 
      Trip.repeating_based_on(repeating_trip).after(pickup_time).not_called_back.destroy_all
    end
  end

  def unlink_past_trips
    if pickup_time < Time.now 
      Trip.repeating_based_on(repeating_trip).today_and_prior.update_all 'repeating_trip_id = NULL'
    else 
      Trip.repeating_based_on(repeating_trip).prior_to(pickup_time).update_all 'repeating_trip_id = NULL'
    end
  end

  def repeating_trip_attributes
    attrs = {}
    RepeatingTrip.trip_attributes.each {|attr| attrs[attr] = self.send(attr) }
    attrs['driver_id'] = repetition_driver_id
    attrs['vehicle_id'] = repetition_vehicle_id
    attrs['customer_informed'] = repetition_customer_informed
    attrs['schedule_attributes'] = {
      repeat:        1,
      interval_unit: "week", 
      start_date:    pickup_time.to_date.to_s,
      interval:      repetition_interval, 
      monday:        repeats_mondays    ? 1 : 0,
      tuesday:       repeats_tuesdays   ? 1 : 0,
      wednesday:     repeats_wednesdays ? 1 : 0,
      thursday:      repeats_thursdays  ? 1 : 0,
      friday:        repeats_fridays    ? 1 : 0,
      saturday:      repeats_saturdays  ? 1 : 0,
      sunday:        repeats_sundays    ? 1 : 0
    }
    attrs
  end

  def driver_is_valid_for_vehicle
    # This will error if a run was found or extended for this vehicle and time, 
    # but the driver for the run is not the driver selected for the trip
    if self.run.try(:driver_id).present? && self.driver_id.present? && self.run.driver_id.to_i != self.driver_id.to_i
      errors.add(:driver_id, "is not the driver for the selected vehicle during this vehicle's run.")
    end
  end

  # Check if the run's vehicle has open capacity at the time of this trip
  def vehicle_has_open_seating_capacity
    if run.try(:vehicle_id).present? && pickup_time.present? && appointment_time.present?
      errors.add(:base, "There's not enough open capacity on this run to accommodate this trip") if run.vehicle.open_seating_capacity(pickup_time, appointment_time, ignore: self) < trip_size
    end
  end

  def compute_run    
    return if run_id || cab || vehicle_id.blank? || provider_id.blank?

    if !pickup_time or !appointment_time 
      return #we'll error out in validation
    end

    #when the trip is saved, we need to find or create a run for it.
    #this will depend on the driver and vehicle.  
    self.run = Run.where("scheduled_start_time <= ? and scheduled_end_time >= ? and vehicle_id=? and provider_id=?", pickup_time, appointment_time, vehicle_id, provider_id).first

    if run.nil?
      #find the next/previous runs for this vehicle and, if necessary,
      #split or change times on them

      previous_run = Run.where("scheduled_start_time <= ? and vehicle_id=? and provider_id=? ", appointment_time, vehicle_id, provider_id).order("scheduled_start_time").last

      next_run = Run.where("scheduled_start_time >= ? and vehicle_id=? and provider_id=? ", pickup_time, vehicle_id, provider_id).order("scheduled_start_time").first

      #there are four possible cases: either the previous or the next run
      #could overlap the trip, or neither could.

      if previous_run and previous_run.scheduled_end_time > pickup_time
        #previous run overlaps trip
        if next_run and next_run.scheduled_start_time < appointment_time
          #next run overlaps trip too
          return handle_overlapping_runs(previous_run, next_run)
        else
          #just the previous run
          if previous_run.scheduled_start_time.to_date != pickup_time.to_date
            self.run = make_run
          else
            self.run = previous_run
            previous_run.update_attributes! scheduled_end_time: run.appointment_time
          end
        end
      else
        if next_run and next_run.scheduled_start_time < appointment_time
          #just the next run
          if next_run.scheduled_start_time.to_date != pickup_time.to_date
            self.run = make_run
          else
            self.run = next_run
            next_run.update_attributes! scheduled_start_time: run.pickup_time
          end
        else
          #no overlap, create a new run
          self.run = make_run
        end
      end
    end

  end

  def handle_overlapping_runs(previous_run, next_run)
    #can we unify the runs?
    if next_run.driver_id == previous_run.driver_id
      self.run = unify_runs(previous_run, next_run)
      return
    end

    #now, can we push the start of the second run later?
    first_trip = next_run.trips.first
    if first_trip.scheduled_start_time > appointment_time
      #yes, we can
      next_run.update_attributes! scheduled_start_time: appointment_time
      previous_run.update_attributes! scheduled_end_time: appointment_time
      self.run = previous_run
    else
      #no, the second run is fixed. Can we push the end of the
      #first run earlier?
      last_trip = previous_run.trips.last
      if last_trip.scheduled_end_time <= pickup_time
        #yes, we can
        previous_run.update_attributes! scheduled_end_time: pickup_time
        next_run.update_attributes! scheduled_start_time: appointment_time
        self.run = next_run
      else
        return false
      end
    end
  end

  def unify_runs(before, after)
    before.update_attributes! scheduled_end_time: after.scheduled_end_time, end_odometer: after.end_odometer
    for trip in after.trips
      trip.run = before
    end
    after.destroy
    return before
  end

  def make_run
    Run.create({
      provider_id:          provider_id,
      date:                 pickup_time.to_date,
      scheduled_start_time: Time.zone.local(
        pickup_time.year,
        pickup_time.month,
        pickup_time.day,
        BUSINESS_HOURS[:start],
        0, 0
      ),
      scheduled_end_time:   Time.zone.local(
        pickup_time.year,
        pickup_time.month,
        pickup_time.day,
        BUSINESS_HOURS[:end],
        0, 0
      ),
      vehicle_id:           vehicle_id,
      driver_id:            driver_id,
      complete:             false,
      paid:                 true
    })
  end

  def format_datetime(datetime)
    if datetime.is_a?(String)
      begin
        Time.zone.parse(datetime.gsub(/\b(a|p)\b/i, '\1m').upcase)
      rescue 
        nil
      end
    else
      datetime
    end
  end
end

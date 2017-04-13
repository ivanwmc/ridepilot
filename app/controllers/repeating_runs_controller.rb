class RepeatingRunsController < ApplicationController
  before_action :set_run, except: [:index, :new, :create]
  authorize_resource

  def index
    @runs = RepeatingRun.active.for_provider(current_provider_id).order(created_at: :desc)
  end

  def new
    @run = RepeatingRun.new(:provider_id => current_provider_id)

    prep_view
    
    respond_to do |format|
      format.html 
    end
  end

  def edit
    prep_view
    
    respond_to do |format|
      format.html 
    end
  end
  
  def show
    prep_view
    
    respond_to do |format|
      format.html
    end
  end

  def create
    @run = RepeatingRun.new(run_params)
    @run.provider = current_provider
    authorize! :manage, @run

    respond_to do |format|
      if @run.is_all_valid?(current_provider_id) && @run.save
        format.html {
          redirect_to @run, :notice => 'Subscription run template was successfully created.'
        }
      else
        prep_view
        format.html { render :action => "new" }
      end
    end

  end

  def update
    authorize! :manage, @run

    @run.assign_attributes(run_params)
    respond_to do |format|
      if @run.is_all_valid?(current_provider_id) && @run.save
        format.html { redirect_to(@run, :notice => 'Run was successfully updated.')  }
      else
        prep_view
        format.html { render :action => "edit"  }
      end
    end
  end

  def destroy
    @run.destroy

    respond_to do |format|
      format.html { redirect_to(repeating_runs_url) }
    end
  end

  private

  def set_run
    @run = RepeatingRun.find_by_id(params[:id])
  end
  
  def run_params
    params.require(:repeating_run).permit(
      :name, 
      :date, 
      :scheduled_start_time, 
      :scheduled_end_time, 
      :vehicle_id, 
      :driver_id, 
      :paid, 
      :repeats_sundays,
      :repeats_mondays,
      :repeats_tuesdays,
      :repeats_wednesdays,
      :repeats_thursdays,
      :repeats_fridays,
      :repeats_saturdays,
      :repetition_driver_id,
      :repetition_interval,
      :repetition_vehicle_id
    )
  end

  def prep_view
    @drivers = Driver.active.where(:provider_id=>@run.provider_id)
    @vehicles = Vehicle.active.where(:provider_id=>@run.provider_id)
  end
end
class VehicleMaintenanceCompliancesController < ApplicationController
  load_and_authorize_resource :vehicle
  load_and_authorize_resource :vehicle_maintenance_compliance, through: :vehicle
  
  respond_to :html, :js

  def index
    @vehicle_maintenance_compliances = @vehicle.vehicle_maintenance_compliances.order(:compliance_mileage)
    @readonly = params[:readonly] == 'true'

    if params[:show_past] != 'true'
      @vehicle_maintenance_compliances = @vehicle_maintenance_compliances.incomplete.limit(3)
    end
  end

  # GET /vehicle_maintenance_compliances/new
  def new
    prep_edit
  end

  # GET /vehicle_maintenance_compliances/1/edit
  def edit
    prep_edit
  end

  # POST /vehicle_maintenance_compliances
  def create
    if @vehicle_maintenance_compliance.save
      respond_to do |format|
        format.html { redirect_to @vehicle, notice: 'Vehicle maintenance compliance was successfully created.' }
        format.js
      end
    else
      prep_edit
      render :new
    end
  end

  # PATCH/PUT /vehicle_maintenance_compliances/1
  def update
    if @vehicle_maintenance_compliance.update(vehicle_maintenance_compliance_params)
      respond_to do |format|
        format.html { redirect_to @vehicle, notice: 'Vehicle maintenance compliance was successfully updated.' }
        format.js
      end
    else
      prep_edit
      render :edit
    end
  end

  # DELETE /vehicle_maintenance_compliances/1
  def destroy
    @vehicle_maintenance_compliance.destroy
    respond_to do |format|
      format.html { redirect_to @vehicle, notice: 'Vehicle maintenance compliance was successfully destroyed.' }
      format.js
    end
  end

  private

  def prep_edit
    @vehicle_maintenance_compliance.document_associations.build
    @vehicle_maintenance_schedule_type = if !params[:vehicle_maintenance_schedule_type_id].blank? 
      VehicleMaintenanceScheduleType.find_by_id(params[:vehicle_maintenance_schedule_type_id])
    else
      @vehicle.vehicle_maintenance_schedule_type || @vehicle_maintenance_compliance.vehicle_maintenance_schedule.try(:vehicle_maintenance_schedule_type)
    end
    @vehicle_maintenance_schedules = @vehicle_maintenance_schedule_type.try(:vehicle_maintenance_schedules) || VehicleMaintenanceSchedule.none
  end

  def vehicle_maintenance_compliance_params
    params.require(:vehicle_maintenance_compliance).permit(:event, :notes, :due_type, :due_date, :due_mileage, :compliance_date, :compliance_mileage, :vehicle_maintenance_schedule_id, document_associations_attributes: [:id, :document_id, :_destroy])
  end
end

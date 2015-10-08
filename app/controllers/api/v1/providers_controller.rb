class API::V1::ProvidersController < API::ApiController
  
  def show
    provider = Provider.find_by_id(params[:provider_id])

    if !provider
      error(:not_found, TranslationEngine.translate_text(:provider_not_exist))
    else
      render json: {}
    end

  end
 
end

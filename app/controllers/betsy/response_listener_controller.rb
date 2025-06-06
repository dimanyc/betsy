class Betsy::ResponseListenerController < ApplicationController
  def etsy_response_listener
    Betsy.request_access_token(params)
    Betsy.upsert_shop_id(params)

    redirect_to(Betsy.redirect_uri_base, allow_other_host: true, notice: "Etsy account connected successfully")
  end
end

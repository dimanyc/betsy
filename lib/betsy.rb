# frozen_string_literal: true

require 'active_support'
require 'faraday'

require_relative 'betsy/version'
require_relative 'betsy/model'
require_relative 'betsy/shop'
require_relative 'betsy/seller_taxonomy'
require_relative 'betsy/shop_listing'
require_relative 'betsy/shop_listing_file'
require_relative 'betsy/shop_listing_image'
require_relative 'betsy/shop_listing_inventory'
require_relative 'betsy/shop_listing_offering'
require_relative 'betsy/shop_listing_product'
require_relative 'betsy/shop_listing_translation'
require_relative 'betsy/shop_listing_variation_image'
require_relative 'betsy/other'
require_relative 'betsy/ledger_entry'
require_relative 'betsy/payment'
require_relative 'betsy/shop_receipt'
require_relative 'betsy/shop_receipt_transaction'
require_relative 'betsy/review'
require_relative 'betsy/shop_shipping_profile'
require_relative 'betsy/shop_production_partner'
require_relative 'betsy/shop_section'
require_relative 'betsy/user'
require_relative 'betsy/user_address'
require_relative 'betsy/error'

module Betsy
  # class Error < StandardError; end

  mattr_accessor :api_key
  mattr_accessor :redirect_uri_base
  mattr_accessor :account_model, default: 'EtsyAccount'
  mattr_accessor :channel_store_model, default: 'ChannelStore'

  ALL_SCOPES = %w[
    address_r
    address_w
    billing_r
    cart_r
    cart_w
    email_r
    favorites_r
    favorites_w
    feedback_r
    listings_d
    listings_r
    listings_w
    profile_r
    profile_w
    recommend_r
    recommend_w
    shops_r
    shops_w
    transactions_r
    transactions_w
  ].freeze

  CODE_CHALLENGE_CHARACTERS = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + ['.', '_', '~', '-']

  def self.authorization_url(user:, scope: ALL_SCOPES)
    if api_key.nil? && redirect_uri_base.nil?
      raise 'Betsy.api_key and Betsy.redirect_uri_base must be set'
    elsif api_key.nil?
      raise 'Betsy.api_key must be set'
    elsif redirect_uri_base.nil?
      raise 'Betsy.redirect_uri_base must be set'
    end

    redirect_uri = "#{redirect_uri_base}/etsy_response_listener"
    scope = scope.join('%20')
    state = generate_state
    code_verifier = generate_code_verifier
    code_challenge = Digest::SHA256.base64digest(code_verifier).tr('+/', '-_').tr('=', '')

    account_class.create!(user_id: user.id, state: state, code_verifier: code_verifier)

    'https://www.etsy.com/oauth/connect' \
      '?response_type=code' \
      "&client_id=#{api_key}" \
      "&redirect_uri=#{redirect_uri}" \
      "&scope=#{scope}" \
      "&state=#{state}" \
      "&code_challenge=#{code_challenge}" \
      '&code_challenge_method=S256'
  end

  def self.request_access_token(params)
    etsy_account = account_class.find_by(state: params[:state])
    unless etsy_account.present?
      raise 'The state provided to /etsy_response_listener was an invalid state, this could be a sign of a CSRF attack'
    end

    options = {
      grant_type: 'authorization_code',
      client_id: api_key,
      redirect_uri: "#{redirect_uri_base}/etsy_response_listener",
      code: params[:code],
      code_verifier: etsy_account.code_verifier
    }
    response = JSON.parse(Faraday.post('https://api.etsy.com/v3/public/oauth/token', options).body)
    etsy_account.access_token = response['access_token']
    etsy_account.refresh_token = response['refresh_token']
    etsy_account.expires_in = response['expires_in']
    etsy_account.last_token_refresh = DateTime.now
    etsy_account.save
  end

  def self.upsert_shop_id(params)
    etsy_account = account_class.find_by(state: params[:state])
    shop_id = User.get_me(etsy_account: etsy_account).shop_id
    channel = Channel.find_by!(name: 'etsy')
    store = channel_store_class.find_or_create_by!(shop_id: shop_id, channel: channel)
    return unless etsy_account.channel_store_id.nil?

    etsy_account.update!(channel_store_id: store.id)
  end

  def self.account_class
    @@account_class ||= account_model.constantize
  end

  def self.channel_store_class
    @@channel_store_class ||= channel_store_model.constantize
  end

  class << self
    private

    def generate_state
      (25...50).map { ('a'..'z').to_a[rand(26)] }.join
    end

    def generate_code_verifier
      (43...128).map { CODE_CHALLENGE_CHARACTERS[rand(CODE_CHALLENGE_CHARACTERS.count)] }.join
    end
  end
end

require_relative 'betsy/engine' if defined?(Rails)

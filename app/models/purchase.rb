# == Schema Information
# Schema version: 20090218144012
#
# Table name: purchases
#
#  id                        :integer(4)      not null, primary key
#  first_name                :string(255)
#  last_name                 :string(255)
#  credit_card_number_ending :string(255)
#  address1                  :string(255)
#  address2                  :string(255)
#  city                      :string(255)
#  state                     :string(255)
#  zip                       :string(255)
#  user_id                   :integer(4)
#  created_at                :datetime
#  updated_at                :datetime
#  total_amount              :decimal(15, 2)
#

class Purchase < ActiveRecord::Base
  class GatewayError < RuntimeError; end

  attr_accessor :credit_card_number, :credit_card_year, :credit_card_month,
    :credit_card_type, :verification_value, :donation_amount, :spotus_donation_amount
  attr_reader :credit_card

  cattr_accessor :gateway

  after_create :associate_donations, :associate_spotus_donations, :associate_credits
  before_create :bill_credit_card, :unless => lambda {|p| p.paypal_transaction? }

  before_validation_on_create :build_credit_card, :set_credit_card_number_ending, :unless => lambda {|p| p.paypal_transaction? }
  before_validation_on_create :set_total_amount
  validates_presence_of :first_name, :last_name, :credit_card_number_ending,
    :address1, :city, :state, :zip, :user_id, :unless => lambda {|p| p.credit_covers_total? || p.paypal_transaction? }

  validates_presence_of :credit_card_number, :credit_card_year,
    :credit_card_type, :credit_card_month, :verification_value,
    :on => :create, :unless => lambda {|p| p.credit_covers_total? || p.paypal_transaction? }

  validate :validate_credit_card, :on => :create, :unless => lambda {|p| p.credit_covers_total? || p.paypal_transaction? }

  belongs_to  :user
  has_many    :donations, :conditions => {:donation_type => "payment"}
  has_many    :credit_pitches, :class_name => "Donation", :conditions => {:donation_type => "credit"}
  has_one     :spotus_donation

  def credit_covers_total?
    self.total_amount == 0
  end

  def credit_covers_partial?
    !credit_covers_total? && credit_to_apply > 0
  end

  def paypal_transaction?
    !paypal_transaction_id.blank?
  end

  def donations=(donations)
    @new_donations = donations
  end
  
  def credit_pitches=(credit_pitches)
    @new_credit_pitches = credit_pitches
  end

  def total_amount
    return self[:total_amount] unless self[:total_amount].blank?
    donations_sum
  end

  def self.valid_donations_for_user?(user, donations)
    donations.all? {|d| d.user == user && d.unpaid? }
  end

  protected

  # total of all donations
  def donations_sum
    amount = 0
    amount += donations.map(&:amount).sum unless donations.blank?
    amount += @new_donations.map(&:amount).sum unless @new_donations.blank?
    amount += spotus_donation[:amount] unless spotus_donation.nil? || spotus_donation[:amount].nil?
    amount
  end

  def set_total_amount
    self[:total_amount] = total_amount
  end

  def build_credit_card
    @credit_card = ActiveMerchant::Billing::CreditCard.new(credit_card_hash)
  end

  def validate_credit_card
    unless credit_card.valid?
      credit_card.errors.each do |field, messages|
        logger.info("Message: " + messages.join(". "))
        messages.each do |message|
          errors.add(:"credit_card_#{field}", message)
        end
      end
    end
  end

  def associate_donations
    (@new_donations || []).each do |donation|
        
      donation.purchase = self
      donation.pay!
      
    end
  end
  
  def associate_credits
    # taking out old accounting...
    #transaction do 
    #  credit_pitch_ids = user.credit_pitches.unpaid.map{|credit_pitch| [credit_pitch.pitch.id]}.join(", ")
    #  credit = Credit.create(:user => user, :description => "Applied to Pitches (#{credit_pitch_ids})",
    #                  :amount => (0 - user.allocated_credits))
    #  user.credit_pitches.unpaid.each do |credit_pitch|
    #    credit_pitch.credit_id = credit.id
    #    credit_pitch.status = "deducted"
    #    credit_pitch.save(false)
    #  end
    #end
  end

  def associate_spotus_donations
    user.unpaid_spotus_donation.update_attribute(:purchase_id, self.id) if user.unpaid_spotus_donation
  end


  def set_credit_card_number_ending
    if credit_card_number
      self.credit_card_number_ending ||= credit_card_number.last(4)
    end
  end

  def credit_to_apply
    return 0 if user.nil?
    [user.allocated_credits, donations_sum].min
  end

  # the gateway expects the total amount to be an integer or a money obj
  def total_amount_for_gateway
    (total_amount.to_f * 100).to_i
  end

  def bill_credit_card
    return true if credit_covers_total?
    
    response = gateway.purchase(total_amount_for_gateway,
                                credit_card,
                                billing_hash)
    unless response.success?
      raise GatewayError, response.message
    end
  end

  private

  def billing_hash
    { :billing_address => { :address1 => address1,
                            :address2 => address2,
                            :city     => city,
                            :state    => state,
                            :zip      => zip,
                            :country  => 'US',
                            :email    => email } }
  end


  def credit_card_hash
    unless gateway.test?
      { :first_name         => first_name,
        :last_name          => last_name,
        :number             => credit_card_number,
        :month              => credit_card_month,
        :year               => credit_card_year,
        :verification_value => verification_value,
        :type               => credit_card_type }
    else
      { :first_name         => first_name,
        :last_name          => last_name,
        :number             => credit_card_number,
        :month              => credit_card_month,
        :year               => credit_card_year,
        :verification_value => verification_value }
    end
  end

  def email
    user.nil? ? nil : user.email
  end

end


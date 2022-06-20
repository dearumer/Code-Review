ROR-UMER-CODE

class censored < ApplicationRecord
  extend FriendlyId
  acts_as_paranoid
  friendly_id :address_line, use: :sequentially_slugged
  delegate :address_line, to: :address, :allow_nil => true
  has_many :runningmenufields
  belongs_to :cancelled_by, class_name: "User", optional: true
  belongs_to :driver, optional: true
  has_paper_trail versions: { scope: -> { order("id desc") } }, if: lambda {|r| r.saved_change_to_delivery_at? }
  accepts_nested_attributes_for :runningmenufields, allow_destroy: true
	enum task_status: [:not_created, :created, :started, :arrived, :completed], _prefix: 'task_status'  
	attr_accessor :updated_from_frontend, :created_from_frontend, :skip_set_dates
	before_validation :check_addresses_count, if: lambda { |r| r.delivery? && r.multiple_del_rests == true }
	validates :runningmenu_type, :delivery_at, presence: true
  validates :runningmenu_type, inclusion: { in: %w(lunch dinner breakfast), message: "Please select Lunch, Dinner or Breakfast of schedules." }
  validates :per_meal_budget, :orders_count, :per_user_copay_amount,  numericality: {:greater_than_or_equal_to => 0}
  validates_length_of :orders_count, in: 1..5, unless: lambda{|r| r.marketplace }

  before_save :before_save_meeting
  after_update :after_update_meeting
  after_save :after_save_meeting
  after_commit :after_commit_meeting, on: [:create, :update], if: lambda { |r| r.skip_set_jobs.nil? }

  def check_addresses_count
    errors.add(:address_ids, "Restaurant locations can't be more than 1 in case of delivery type as delivery")
    self.delivery_type = Runningmenu.delivery_types[self.delivery_type_was] unless self.new_record?
  end

  def generate_invoice_job
    if self.orders.active.count
      InvoiceWorker.perform_at(self.delivery_at.utc, self.id)
      self.update_column(:enqueued_for_invoice, true)
    end
  end

  def addresses_count_other_than_bev_and_more
    self.addresses.active.joins("INNER JOIN restaurants ON restaurants.id = addresses.addressable_id AND addresses.addressable_type = 'Restaurant' AND restaurants.name <> '#{ENV["BEV_AND_MORE"]}'").count
  end

  def set_fleet_create_task_job
    if self.fleet_create_task_job_id.present?
      job = Sidekiq::ScheduledSet.new.find_job(self.fleet_create_task_job_id)
      job.delete unless job.nil?
    end
    job_id = FleetCreateTaskWorker.perform_at(self.cutoff_at.utc, self.id)
    self.fleet_create_task_job_id.blank? ? self.update_attributes(fleet_create_task_job_id: job_id, skip_set_dates: true) : self.update_columns(fleet_create_task_job_id: job_id)
  end


  def sample_code
  	begin
	    pickup_task = Onfleet::Task.create(
	      destination: {
	        address: {
	          unparsed: 'valid address goes here'
	        },
	      },
	      recipients: [],
	      pickup_task: true,
	      dependencies: dependency.flatten,
	      complete_before: self.delivery? ? (self.delivery_at_timezone.to_f * 1000).to_i : ((self.delivery_at_timezone - 60.minutes).to_f * 1000).to_i,
	      complete_after: self.delivery? ? (self.delivery_at_timezone.to_f * 1000).to_i : ((self.delivery_at_timezone - 70.minutes).to_f * 1000).to_i,
	      notes: "Message message message.#{b_orders}",
	      quantity: beverages_orders.sum(&:quantity),
	      service_time: 10,
	    )
	    if pickup_task.present?
	      if self.driver.present? && self.driver.worker_id.present?
	        Onfleet::Task.update(pickup_task.id, {worker: self.driver.worker_id})
	      end
	      self.update_column(:pickup_task_id, pickup_task.id)
	      puts "OnFleet: Task created for abc"
	    else
	      puts "OnFleet: Task failed to for abc"
	    end
	  rescue StandardError => e
	    subject = "OnFleet: Pickup Task failed for abc #{self.id}"
	    email = ScheduleMailer.onfleet_task_failed(self, subject, e.message)
	    EmailLog.create(sender: ENV['RECIPIENT_EMAIL'], subject: email.subject, recipient: email.to.first, body: Base64.encode64(email.body.raw_source))
	    puts "OnFleet: #{e.message}"
	  end
  end

  def menu_delivery_at
    errors.add(:delivery_at, "Can't be updated, delivery date has been passed.") if self.delivery_at_was < Time.current && !self.pending?
  end

	scope :last_imported, -> {
    where("DATE(created_at) = ?",BusinessAddress.maximum('DATE(created_at)')).order(id: :desc)
  }

  scope :today_runningmenus, -> (time_zone) {
    where(delivery_at: Time.current.in_time_zone(time_zone).beginning_of_day..Time.current.in_time_zone(time_zone).end_of_day)
  }

  scope :tomorrow_runningmenus, -> (time_zone) {
    where(delivery_at: 1.days.from_now.in_time_zone(time_zone).beginning_of_day..1.days.from_now.in_time_zone(time_zone).end_of_day)
  }

  scope :seven_day_runningmenus, -> (time_zone) {
    where(delivery_at: Time.current.in_time_zone(time_zone).beginning_of_day..7.days.since)
  }

  scope :thirty_day_runningmenus, -> (time_zone) {
    where(delivery_at: Time.current.in_time_zone(time_zone).beginning_of_day..30.days.since)
  }

  ransacker :by_days, formatter: proc {|value|
    time_zone = value.split("--")[1]
    value = value.split("--")[0]
    results = Runningmenu.today_runningmenus(time_zone).map(&:id) if value == "Today"
    results = Runningmenu.tomorrow_runningmenus(time_zone).map(&:id) if value == "Tomorrow"
    results = Runningmenu.seven_day_runningmenus(time_zone).map(&:id) if value ==  "Next 7 Days"
    results = Runningmenu.thirty_day_runningmenus(time_zone).map(&:id) if value == "Next 30 Days"
    results = results.present? ? results : nil
   } do |parent|
    parent.table[:id]
  end

  def user_remaining_budget(user_id, share_meeting_id, exclude_order_id)
    where = "orders.deleted_at IS NULL AND orders.runningmenu_id = #{self.id} AND orders.status = 0"
    where += " AND orders.share_meeting_id = #{share_meeting_id}" if share_meeting_id.present?
    where += " AND orders.user_id = #{user_id}" if user_id.present?
    where += " AND orders.id != #{exclude_order_id}" if exclude_order_id.present?
    already_used_budget = Order.find_by_sql("SELECT SUM((company_price + CASE user_markup WHEN false THEN site_price ELSE 0 END )) AS total FROM orders WHERE #{where}")
    remaining_budget = self.per_meal_budget - already_used_budget.last.total.to_f
    remaining_budget > 0 ? remaining_budget : 0
  end

class censored < ActiveRecord::Migration
  def self.up
    execute "CREATE OR REPLACE FUNCTION rep_budget_chart(p_start_date DATE, p_end_date DATE, p_group_by TEXT, p_company_ids TEXT DEFAULT NULL, p_address_ids TEXT DEFAULT NULL)
      RETURNS JSON
        AS $$
        DECLARE
          SQL TEXT := '';
          total_budget DECIMAL := 0.0;
          rep_obj RECORD;
          budget_graph JSON;
          budget_analysis_graph JSON[];
        BEGIN
          -- Budget Analyses chart
          SQL = 'SELECT (SUM(food_cost)::DECIMAL) AS total FROM rep_budget_analyses WHERE dated_on >= ''' || p_start_date || ''' AND dated_on <= ''' || p_end_date || '''';
          IF p_company_ids IS NOT NULL THEN
            SQL = SQL || ' AND company_id IN(' || p_company_ids || ')';
          END IF;
          IF p_address_ids IS NOT NULL THEN
            SQL = SQL || ' AND address_id IN(' || p_address_ids || ')';
          END IF;
          FOR rep_obj IN EXECUTE SQL
          LOOP
            IF rep_obj.total IS NOT NULL THEN
              total_budget := rep_obj.total::DECIMAL;
            END IF;
          END LOOP;
          SQL = 'SELECT department, ROUND(SUM(percentage), 2) AS percentage FROM (';
          SQL = SQL || 'SELECT ('|| p_group_by ||') AS department, (SUM(food_cost)::DECIMAL/(' || total_budget || ') * 100) AS percentage FROM rep_budget_analyses GROUP BY '|| p_group_by ||', company_id, address_id, dated_on HAVING dated_on >= ''' || p_start_date || ''' AND dated_on <= ''' || p_end_date || '''';
          IF p_company_ids IS NOT NULL THEN
            SQL = SQL || ' AND company_id IN(' || p_company_ids || ')';
          END IF;
          IF p_address_ids IS NOT NULL THEN
            SQL = SQL || ' AND address_id IN(' || p_address_ids || ')';
          END IF;
          SQL = SQL || ') AS tbl GROUP BY tbl.department';
          FOR rep_obj IN EXECUTE SQL
          LOOP
            SELECT JSON_BUILD_OBJECT('id', rep_obj.department, 'label', rep_obj.department, 'value', rep_obj.percentage) INTO budget_graph;
            budget_analysis_graph := ARRAY_APPEND(budget_analysis_graph, budget_graph);
          END LOOP;
          -- Build the JSON Response:
          RETURN ( SELECT JSON_BUILD_OBJECT('budget_analysis_graph', COALESCE(budget_analysis_graph, ARRAY[]::json[]) ));
        END; $$
    LANGUAGE 'plpgsql';"
  end

  def self.down
    execute "DROP FUNCTION rep_budget_chart(p_start_date DATE, p_end_date DATE, p_group_by TEXT, p_company_ids TEXT, p_address_ids TEXT)"
  end
end


class censored < ActiveRecord::Migration
  def self.up
    execute "CREATE VIEW ORDER_NOT_INVOICED_VIEW AS
      SELECT orders.id, (CASE WHEN (share_meetings.first_name != '' OR share_meetings.last_name != '') THEN CONCAT(share_meetings.first_name, ' ' , share_meetings.last_name) ELSE CONCAT(users.first_name, ' ' , users.last_name) END) AS user_name, companies.name, restaurants.name AS restaurant_name, addresses.address_line AS company_location, fooditems.name AS fooditem_name, runningmenus.id AS runningmenu_id, orders.price, orders.company_price, orders.user_price, orders.site_price, orders.quantity, orders.total_price, orders.discount, (orders.total_price - orders.discount) AS discounted_total_price,
      runningmenus.delivery_instructions, orders.invoice_id AS invoice_id,  orders.created_at, runningmenus.delivery_at, (CASE WHEN orders.status = 0 THEN 'active' ELSE 'cancelled' END) AS status FROM orders
      INNER JOIN runningmenus ON runningmenus.id = orders.runningmenu_id AND runningmenus.deleted_at IS NULL
      INNER JOIN companies ON companies.id = runningmenus.company_id AND companies.deleted_at IS NULL
      INNER JOIN restaurants ON restaurants.id = orders.restaurant_id AND restaurants.deleted_at IS NULL
      INNER JOIN addresses ON runningmenus.address_id = addresses.id
      INNER JOIN fooditems ON orders.fooditem_id = fooditems.id
      LEFT JOIN share_meetings ON orders.share_meeting_id = share_meetings.id
      INNER JOIN users ON orders.user_id = users.id
      WHERE orders.deleted_at IS NULL AND orders.status = '#{Order.statuses[:active]}'
      AND orders.invoice_id IS NULL
      GROUP BY orders.id, addresses.id, runningmenus.id, fooditems.id, restaurants.id, share_meetings.id, users.id, companies.id
      ORDER BY runningmenus.delivery_at DESC;"
  end
  def self.down
    execute "DROP VIEW IF EXISTS ORDER_NOT_INVOICED_VIEW;";
  end
end

class censored
  include Sidekiq::Worker
  sidekiq_options queue: :admin_cutoff_reached_queue

  def perform(runningmenu_id)
    runningmenu = Runningmenu.find runningmenu_id
    begin
      FileUtils.mkdir_p 'public/ordersummary'
      FileUtils.mkdir_p 'public/download_pdfs'
      FileUtils.mkdir_p 'public/fax_summary'
      
      puts "Changes Email At Admin Cutoff start for scheduler #{runningmenu.id} - #{Time.current}"
      orders = Order.find_by_sql("select * from order_at_admin_cutoff(#{runningmenu.id})")
      unless orders.blank?
        email = OrderMailer.orders_diff_at_admin_cuttof(runningmenu, orders)
        EmailLog.create(sender: ENV['RECIPIENT_EMAIL'], subject: email.subject, recipient: email.to.first, body: Base64.encode64(email.body.raw_source))
      end
      Order.assign_groups_to_orders_after_cutoff(runningmenu) if runningmenu.company.enable_grouping_orders
      runningmenu.addresses.active.each do |address|
        puts "Admin Cutoff start for address #{address.id} and runningmenu #{runningmenu.id} - #{Time.current}"
        OrdersDetailToRestaurantAtAdminCutoffJob.perform_later(runningmenu, address)
      end
      runningmenu.assign_attributes(admin_cutoff_reached_job_status: Runningmenu.admin_cutoff_reached_job_statuses[:processed], skip_set_dates: true, skip_set_jobs: true)
      runningmenu.generate_invoice_job if runningmenu.delivery? && !runningmenu.enqueued_for_invoice
      puts "Admin cutoff processing end for scheduler #{runningmenu.id} - #{Time.current}"
    rescue StandardError => e
      runningmenu.assign_attributes(admin_cutoff_reached_job_status: Runningmenu.admin_cutoff_reached_job_statuses[:not_processed], admin_cutoff_reached_job_error: e.message, skip_set_dates: true, skip_set_jobs: true)
    end
    runningmenu.save(validate: false)
  end
end

validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a 'example@example.com ' " }, allow_blank: true
accepts_nested_attributes_for :addresses, allow_destroy: true

def as_json(options = nil)
  super({ only: [
    :id,
    :name,
    :email,
  ]}.merge(options || {}))
end

validates_format_of :card_number,
  :with => /[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}/,
  :message => "- Card numbers must be in xxxx-xxxx-xxxx-xxxx format.", if: lambda { |b| b.credit_card? && b.card_number.present?}
  validates :expiry_month, numericality: {greater_than_or_equal_to: 1, less_than_or_equal_to: 12}, if: lambda { |b| b.credit_card? && b.expiry_month.present?}
  validates :expiry_year, numericality: {greater_than_or_equal_to: 1900, less_than_or_equal_to: 2050}, if: lambda { |b| b.credit_card? && b.expiry_year.present?}
  validates :delivery_fee, numericality: {:greater_than_or_equal_to => 0}
  after_validation :stripe_credit_card_payment, if: lambda { |b| (b.credit_card? && ((b.change_card.present? && b.change_card == '1') || b.will_save_change_to_token? || (b.change_card.present? && !b.change_card == '1') || b.updated_from_backend))}
  attr_accessor :card_number, :cvc, :expiry_month, :expiry_year, :change_card, :updated_from_backend

  def stripe_credit_card_payment
    begin
      if self.token.present? && !(self.change_card.present? && self.change_card == '1')
        token = self.token
      else
        tk = Stripe::Token.create({
          card: {
            number: self.card_number,
            exp_month: self.expiry_month,
            exp_year: self.expiry_year,
            cvc: self.cvc,
          },
        })
      end
      if tk.present?
        token = tk.id
        self.stripe_cc_id = tk.card.id
      end
      if token.present?
        self.token = token
        customer = Stripe::Customer.create({
          description: "Customer for #{self.company.name}",
          source: token
        })
        if customer.present?
          self.customer_id = customer.id
        end
      end
    rescue Stripe::CardError => e
      errors.add(:card_number, "Credit Card failed to save due to #{e.message}")
    rescue => e
      errors.add(:card_number, "Credit Card failed to save due to #{e.message}")
    end
  end

  class ConversationsChannel < ApplicationCable::Channel
	  def subscribed
	    stream_from "conversations_#{params[:conversation_id]}_channel"
	  end

	  def unsubscribed
	    # Any cleanup needed when channel is unsubscribed
	    $redis.del("staff_#{params["user_id"]}_online") unless params["user_id"].blank?
	  end

	  def send_message(data)
	    Chat.create!(conversation_id: data[:conversation_id] || data["conversation_id"], user_id: data[:user_id] || data["user_id"], message: data[:message] || data["message"])
	  end

	  def update_read(data)
	    ChatsRecipient.where('conversation_id = ? AND user_id = ? AND chat_id IN (?)', data['conversation_id'], data['user_id'], data['chat_ids']).update_all(read: true)
	  end
	end

	module ApplicationCable
	  class Connection < ActionCable::Connection::Base
	    identified_by :current_user

	    def connect
	      self.current_user = find_verified_user
	      logger.add_tags 'ActionCable', current_user.email
	    end

	    def disconnect
	      unless current_user.nil?
	        $redis.del("staff_#{current_user.id}_online") unless $redis.get("staff_#{current_user.id}_online").nil?
	      end
	    end

	    protected

	    def find_verified_user # this checks whether a user is authenticated with devise
	      params = request.query_parameters()
	      logger.add_tags 'ActionCable', params

	      if !params['uid'].blank? && !params['client'].blank? && !params['access-token'].blank?
	        uid = params['uid']
	        client = params['client']
	        access_token = params['access-token']
	        verified_user = User.find_by(email: uid)
	        if verified_user && verified_user.valid_token?(access_token, client)
	          $redis.set("staff_#{verified_user.id}_online", "1")
	          verified_user
	        else
	          reject_unauthorized_connection
	        end
	      else
	        if verified_user = User.find_by(id: cookies.signed['user.id'])
	          $redis.set("staff_#{verified_user.id}_online", "1")
	          verified_user
	        else
	          reject_unauthorized_connection
	        end
	      end
	    end
	  end
	end

module Api
  module V1
    class ApiController < ActionController::Base
      include DeviseTokenAuth::Concerns::SetUserByToken
      protect_from_forgery with: :null_session
      before_action :authenticate_user!, only: :eway_credentials
      RecoverableExceptions = [
          ActiveRecord::RecordNotUnique,
          ActiveRecord::RecordInvalid,
          ActiveRecord::RecordNotSaved
      ]

      rescue_from Exception do |e|
        error(E_API, "An internal API error occured. Please try again.\n #{e.message}")
      end

      def error(code = E_INTERNAL, message = 'API Error')
        render json: {
          status: STATUS_ERROR,
          error_no: code,
          message: message
        }, :status => HTTP_CRASH
      end

      def render_resource_failure(resource, resource_name)
        render :json => {
          status: FAIL_STATUS,
          resource_name.to_sym => resource,
          full_messages: resource.errors.full_messages
        }, status: HTTP_FAIL
      end
		end
	end
end

json.set! 'general_recommendations' do
  json.array!(@checkin.checkin_generals) do |checkin_general|
    json.section_name checkin_general.section.name
    json.extract! checkin_general, :text_to_display, :note
  end
end
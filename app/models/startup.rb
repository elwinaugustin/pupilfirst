# encoding: utf-8
# frozen_string_literal: true

class Startup < ActiveRecord::Base
  include FriendlyId

  # For an explanation of these legacy values, see linked trello card.
  #
  # @see https://trello.com/c/SzqE6l8U
  LEGACY_STARTUPS_COUNT = 849
  LEGACY_INCUBATION_REQUESTS = 5281

  REGISTRATION_TYPE_PRIVATE_LIMITED = 'private_limited'.freeze
  REGISTRATION_TYPE_PARTNERSHIP = 'partnership'.freeze
  REGISTRATION_TYPE_LLP = 'llp'.freeze # Limited Liability Partnership

  MAX_PITCH_CHARACTERS = 140 unless defined?(MAX_PITCH_CHARACTERS)
  MAX_PRODUCT_DESCRIPTION_CHARACTERS = 150
  MAX_CATEGORY_COUNT = 3

  APPROVAL_STATUS_UNREADY = 'unready'.freeze
  APPROVAL_STATUS_PENDING = 'pending'.freeze
  APPROVAL_STATUS_APPROVED = 'approved'.freeze
  APPROVAL_STATUS_REJECTED = 'rejected'.freeze
  APPROVAL_STATUS_DROPPED_OUT = 'dropped-out'.freeze

  PRODUCT_PROGRESS_IDEA = 'idea'.freeze
  PRODUCT_PROGRESS_MOCKUP = 'mockup'.freeze
  PRODUCT_PROGRESS_PROTOTYPE = 'prototype'.freeze
  PRODUCT_PROGRESS_PRIVATE_BETA = 'private_beta'.freeze
  PRODUCT_PROGRESS_PUBLIC_BETA = 'public_beta'.freeze
  PRODUCT_PROGRESS_LAUNCHED = 'launched'.freeze

  INCUBATION_LOCATION_KOCHI = 'kochi'.freeze
  INCUBATION_LOCATION_VISAKHAPATNAM = 'visakhapatnam'.freeze
  INCUBATION_LOCATION_KOZHIKODE = 'kozhikode'.freeze

  SV_STATS_LINK = 'bit.ly/svstats2'.freeze

  def self.valid_agreement_durations
    { '1 year' => 1.year, '2 years' => 2.years, '5 years' => 5.years }
  end

  def self.valid_incubation_location_values
    [INCUBATION_LOCATION_KOCHI, INCUBATION_LOCATION_VISAKHAPATNAM, INCUBATION_LOCATION_KOZHIKODE]
  end

  def self.valid_product_progress_values
    [
      PRODUCT_PROGRESS_IDEA, PRODUCT_PROGRESS_MOCKUP, PRODUCT_PROGRESS_PROTOTYPE, PRODUCT_PROGRESS_PRIVATE_BETA,
      PRODUCT_PROGRESS_PUBLIC_BETA, PRODUCT_PROGRESS_LAUNCHED
    ]
  end

  def self.valid_registration_types
    [REGISTRATION_TYPE_PRIVATE_LIMITED, REGISTRATION_TYPE_PARTNERSHIP, REGISTRATION_TYPE_LLP]
  end

  def self.valid_approval_status_values
    [
      APPROVAL_STATUS_UNREADY, APPROVAL_STATUS_PENDING, APPROVAL_STATUS_APPROVED, APPROVAL_STATUS_REJECTED,
      APPROVAL_STATUS_DROPPED_OUT
    ]
  end

  scope :batched, -> { where.not(batch_id: nil) }
  scope :unready, -> { where(approval_status: [APPROVAL_STATUS_UNREADY, nil]) }
  scope :not_unready, -> { where.not(approval_status: [APPROVAL_STATUS_UNREADY, nil]) }
  scope :pending, -> { where(approval_status: APPROVAL_STATUS_PENDING) }
  scope :approved, -> { where(approval_status: APPROVAL_STATUS_APPROVED) }
  scope :rejected, -> { where(approval_status: APPROVAL_STATUS_REJECTED) }
  scope :dropped_out, -> { where(approval_status: APPROVAL_STATUS_DROPPED_OUT) }
  scope :not_dropped_out, -> { where.not(approval_status: APPROVAL_STATUS_DROPPED_OUT) }
  scope :incubation_requested, -> { where(approval_status: [APPROVAL_STATUS_PENDING, APPROVAL_STATUS_REJECTED, APPROVAL_STATUS_APPROVED]) }
  scope :agreement_signed, -> { where 'agreement_first_signed_at IS NOT NULL' }
  scope :agreement_live, -> { where('agreement_ends_at > ?', Time.now) }
  scope :agreement_expired, -> { where('agreement_ends_at < ?', Time.now) }
  scope :physically_incubated, -> { agreement_live.where(physical_incubatee: true) }
  scope :without_founders, -> { where.not(id: (User.pluck(:startup_id).uniq - [nil])) }
  scope :student_startups, -> { joins(:founders).where.not(users: { university_id: nil }).uniq }
  scope :kochi, -> { where incubation_location: INCUBATION_LOCATION_KOCHI }
  scope :visakhapatnam, -> { where incubation_location: INCUBATION_LOCATION_VISAKHAPATNAM }
  scope :timeline_verified, -> { joins(:timeline_events).where(timeline_events: { verified_status: TimelineEvent::VERIFIED_STATUS_VERIFIED }).distinct }
  scope :batched_and_approved, -> { batched.approved }

  # Returns the latest verified timeline event that has an image attached to it.
  # Do not return private events!
  #
  # @return TimelineEvent
  def showcase_timeline_event
    timeline_events.verified.has_image.order('verified_at DESC').detect do |timeline_event|
      !timeline_event.private?
    end
  end

  # Returns startups that have accrued no karma points for last week (starting monday). If supplied a date, it
  # calculates for week bounded by that date.
  def self.inactive_for_week(date: 1.week.ago)
    date = date.in_time_zone('Asia/Calcutta')

    # First, find everyone who doesn't fit the criteria.
    startups_with_karma_ids = joins(:karma_points)
      .where(karma_points: { created_at: (date.beginning_of_week + 18.hours)..(date.end_of_week + 18.hours) })
      .pluck(:id)

    # Filter them out.
    batched.approved.where.not(id: startups_with_karma_ids)
  end

  def self.endangered
    startups_with_karma_ids = joins(:karma_points)
      .where(karma_points: { created_at: 3.weeks.ago..Time.now })
      .pluck(:id)
    batched.approved.where.not(id: startups_with_karma_ids)
  end

  # Batched & approved startups that don't have un-expired targets.
  def self.without_live_targets
    # Where status is pending.
    without_live_targets_ids = joins(:targets).where(targets: { status: Target::STATUS_PENDING })

    # Where due date isn't set, or hasn't expired.
    without_live_targets_ids = without_live_targets_ids.where('targets.due_date IS NULL OR targets.due_date > ?', Time.now)

    # All except the above.
    batched.approved.where.not(id: without_live_targets_ids)
  end

  def self.with_targets_completed_last_week
    with_completed_targets.where('targets.completed_at > ?', 1.week.ago)
  end

  def self.with_completed_targets
    joins(:targets).where(targets: { status: Target::STATUS_DONE })
  end

  # Find all by specific category.
  def self.startup_category(category)
    joins(:startup_categories).where(startup_categories: { id: category.id })
  end

  has_many :founders, -> { where('is_founder = ?', true) }, class_name: 'User', foreign_key: 'startup_id' do
    def <<(founder)
      founder.update_attributes!(is_founder: true)
      super founder
    end
  end

  has_and_belongs_to_many :startup_categories do
    def <<(_category)
      fail 'Use startup_categories= to enforce startup category limit'
    end
  end

  has_many :timeline_events, dependent: :destroy
  has_many :startup_feedback, dependent: :destroy
  has_many :karma_points, through: :founders
  has_many :targets, dependent: :destroy
  has_many :connect_requests, dependent: :destroy
  has_many :team_members, dependent: :destroy

  # Allow statup to accept nested attributes for users
  # has_many :users
  # accepts_nested_attributes_for :users

  has_one :admin, -> { where(startup_admin: true) }, class_name: 'User', foreign_key: 'startup_id'
  accepts_nested_attributes_for :admin

  belongs_to :batch

  attr_accessor :validate_web_mandatory_fields
  attr_reader :validate_registration_type

  # Some fields are mandatory when editing from web.
  validates_presence_of :product_name, :presentation_link, :product_description, :incubation_location, if: :validate_web_mandatory_fields

  # Registration type is required when registering.
  validates_presence_of :registration_type, if: ->(startup) { startup.validate_registration_type }

  validate :valid_founders?

  # TODO: Ensure this is take care of when rewriting incubation without wizard
  # validates_associated :founders, unless: ->(startup) { startup.incubation_step_1? }

  # Registration type should be one of Pvt. Ltd., Partnership, or LLC.
  validates :registration_type,
    inclusion: { in: valid_registration_types },
    allow_nil: true

  # Product Progress should be one of acceptable list.
  validates :product_progress,
    inclusion: { in: valid_product_progress_values },
    allow_nil: true,
    allow_blank: true

  # Product Progress should be one of acceptable list.
  validates :incubation_location,
    inclusion: { in: valid_incubation_location_values },
    allow_nil: true

  # validates_presence_of :name, if: ->(startup){@full_validation }
  # validates_presence_of :address, if: ->(startup){@full_validation }
  # validates_presence_of :email
  # validates_presence_of :phone

  # Only accept both agreement dates together.
  validates_presence_of :agreement_first_signed_at, if: ->(startup) { startup.agreement_last_signed_at.present? || startup.agreement_duration.present? }
  validates_presence_of :agreement_last_signed_at, if: ->(startup) { startup.agreement_first_signed_at.present? || startup.agreement_duration.present? }

  validates_numericality_of :pin, allow_nil: true, greater_than_or_equal_to: 100_000, less_than_or_equal_to: 999_999 # PIN Code is always 6 digits

  validates_length_of :product_description,
    maximum: MAX_PRODUCT_DESCRIPTION_CHARACTERS,
    message: "must be within #{MAX_PRODUCT_DESCRIPTION_CHARACTERS} characters"

  validates_length_of :pitch,
    maximum: MAX_PITCH_CHARACTERS,
    message: "must be within #{MAX_PITCH_CHARACTERS} characters"

  # New set of validations for incubation wizard
  store :metadata, accessors: [:updated_from]
  validates_presence_of :product_name, :presentation_link, :product_description, :incubation_location, if: :incubation_step_2?

  validates_numericality_of :team_size, greater_than: 0, allow_blank: true
  validates_numericality_of :women_employees, greater_than_or_equal_to: 0, allow_blank: true
  validates_numericality_of :revenue_generated, greater_than_or_equal_to: 0, allow_blank: true

  validates_presence_of :product_name

  def incubation_step_1?
    updated_from == 'user_profile'
  end

  def incubation_step_2?
    updated_from == 'startup_profile'
  end

  before_validation do
    # Set registration_type to nil if its set as blank from backend.
    self.registration_type = nil if registration_type.blank?

    # If supplied \r\n for line breaks, replace those with just \n so that length validation works.
    self.product_description = product_description.gsub("\r\n", "\n") if product_description

    # If slug isn't supplied, set one.
    self.slug = generate_randomized_slug if slug.blank?

    # Default product name to 'Untitled Product' if absent
    self.product_name ||= 'Untitled Product'
  end

  before_destroy do
    # Clear out associations from associated Users (and pending ones).
    User.where(startup_id: id).update_all(startup_id: nil, startup_admin: nil, is_founder: nil)
  end

  # Friendly ID!
  friendly_id :slug
  validates_format_of :slug, with: /\A[a-z0-9\-_]+\z/i, allow_nil: true

  # Backend users will see agreement duration as being nil when attempting to edit. This allows them to save edits
  # without picking a value.
  def agreement_duration
    nil
  end

  # Let's allow backend users to edit agreement_ends at as a duration instead of setting absolute date.
  def agreement_duration=(duration)
    @agreement_duration = duration unless duration.blank?
  end

  # Reader for the validator.
  attr_reader :agreement_duration

  before_save do
    # If agreement duration is available, store that as agreement_ends_at.
    if agreement_duration
      self.agreement_ends_at = (agreement_last_signed_at + agreement_duration.to_i).to_date
    end

    self.agreement_ends_at = nil if agreement_first_signed_at.nil? && agreement_last_signed_at.nil?
  end

  def approval_status
    super || APPROVAL_STATUS_UNREADY
  end

  def approved?
    approval_status == APPROVAL_STATUS_APPROVED
  end

  def pending?
    approval_status == APPROVAL_STATUS_PENDING
  end

  def unready?
    approval_status == APPROVAL_STATUS_UNREADY
  end

  def rejected?
    approval_status == APPROVAL_STATUS_REJECTED
  end

  def dropped_out?
    approval_status == APPROVAL_STATUS_DROPPED_OUT
  end

  def valid_founders?
    errors.add(:founders, 'should have at least one founder') if founders.nil? || founders.size < 1
  end

  def batched?
    batch.present?
  end

  mount_uploader :logo, LogoUploader
  process_in_background :logo

  normalize_attribute :name, :pitch, :product_description, :email, :phone, :revenue_generated, :team_size, :women_employees, :approval_status

  attr_accessor :full_validation

  after_initialize ->() { @full_validation = true }

  normalize_attribute :website do |value|
    case value
      when '' then
        nil
      when nil then
        nil
      when %r{^https?://.*} then
        value
      else
        "http://#{value}"
    end
  end

  normalize_attribute :twitter_link do |value|
    case value
      when %r{^https?://(www\.)?twitter.com.*} then
        value
      when /^(www\.)?twitter\.com.*/ then
        "https://#{value}"
      when '' then
        nil
      when nil then
        nil
      else
        "https://twitter.com/#{value}"
    end
  end

  normalize_attribute :facebook_link do |value|
    case value
      when %r{^https?://(www\.)?facebook.com.*} then
        value
      when /^(www\.)?facebook\.com.*/ then
        "https://#{value}"
      when '' then
        nil
      when nil then
        nil
      else
        "https://facebook.com/#{value}"
    end
  end

  def founder_ids=(list_of_ids)
    users_list = User.find list_of_ids.map(&:to_i).select { |e| e.is_a?(Integer) && e > 0 }
    users_list.each { |u| founders << u }
  end

  validate :category_count

  def category_count
    return unless @category_count_exceeded || startup_categories.count > MAX_CATEGORY_COUNT
    errors.add(:startup_categories, "Can't have more than 3 categories")
  end

  # Custom setter for startup categories.
  #
  # @param [String, Array] category_entries Array of Categories or comma-separated Category ID-s.
  def startup_categories=(category_entries)
    parsed_categories = if category_entries.is_a? String
      category_entries.split(',').map do |category_id|
        StartupCategory.find(category_id)
      end
    else
      category_entries
    end

    # Enforce maximum count for categories.
    if parsed_categories.count > MAX_CATEGORY_COUNT
      @category_count_exceeded = true
    else
      super parsed_categories
    end
  end

  def self.current_startups_split
    {
      'Unready' => unready.count,
      'Pending' => pending.count,
      'Approved' => approved.count,
      'Rejected' => rejected.count,
      'Dropped-out' => dropped_out.count
    }
  end

  def self.current_startups_split_by_incubation_location(incubation_location)
    {
      'Pending' => pending.where(incubation_location: incubation_location).count,
      'Approved' => approved.where(incubation_location: incubation_location).count,
      'Rejected' => rejected.where(incubation_location: incubation_location).count,
      'Dropped-out' => dropped_out.where(incubation_location: incubation_location).count
    }
  end

  # Return startups with agreement signed on or after Nov 5, 2014.
  #
  # @see https://trello.com/c/SzqE6l8U
  def self.agreement_signed_filtered
    where('agreement_first_signed_at > ?', Time.parse('2014-11-05 00:00:00 +0530'))
  end

  def agreement_live?
    try(:agreement_ends_at).to_i > Time.now.to_i
  end

  def founder?(user)
    return false unless user
    user.is_founder? && user.startup_id == id
  end

  def possible_founders
    founders + User.non_founders
  end

  def phone
    admin.try(:phone)
  end

  # E-mail address of person to contact in case startup is rejected.
  def rejection_contact
    case incubation_location
      when INCUBATION_LOCATION_VISAKHAPATNAM
        'vasu@startupvillage.in'
      when INCUBATION_LOCATION_KOCHI
        'kiran@startupvillage.in'
      when INCUBATION_LOCATION_KOZHIKODE
        'kiran@startupvillage.in'
      else
        'kiran@startupvillage.in'
    end
  end

  def self.new_incubation!(user)
    startup = Startup.new
    startup.founders << user
    startup.save!

    user.update!(startup_admin: true)
    startup
  end

  def cofounders(user)
    founders - [user]
  end

  def finish_incubation_flow!
    # Set approval status to pending to end incubation flow.
    self.approval_status = Startup::APPROVAL_STATUS_PENDING

    regenerate_slug!

    # Send e-mail to founder notifying him / her of pending status.
    UserMailer.incubation_request_submitted(admin).deliver_later
  end

  def generate_randomized_slug
    if name.present?
      "#{name.parameterize}-#{rand 1000}"
    elsif product_name.present?
      "#{product_name.parameterize}-#{rand 1000}"
    else
      "nameless-#{SecureRandom.hex(2)}"
    end
  end

  def regenerate_slug!
    # Create slug from name.
    self.slug = product_name.parameterize

    begin
      save!
    rescue ActiveRecord::RecordNotUnique
      # If it's taken, try adding a random number.
      self.slug = "#{product_name.parameterize}-#{rand 1000}"
      retry
    end
  end

  def incubation_parameters_available?
    product_name.present? &&
      product_description.present? &&
      presentation_link.present? &&
      incubation_location.present?
  end

  ####
  # Temporary mentor and investor checks which always return false
  ####
  def mentors?
    false
  end

  def investors?
    false
  end

  # returns the date of the earliest verified timeline entry
  def earliest_event_date
    timeline_events.verified.order(:event_on).first.try(:event_on)
  end

  # returns the date of the latest verified timeline entry
  def latest_event_date
    timeline_events.verified.order(:event_on).last.try(:event_on)
  end

  # returns the latest 'moved_to_x_stage' timeline entry
  def latest_change_of_stage
    timeline_events.verified.where(timeline_event_type: TimelineEventType.moved_to_stage).order(event_on: :desc).includes(:timeline_event_type).first
  end

  # returns all timeline entries posted in the current stage i.e after the last 'moved_to_x_stage' timeline entry
  def current_stage_events
    if latest_change_of_stage.present?
      timeline_events.where('event_on > ?', latest_change_of_stage.event_on)
    else
      timeline_events
    end
  end

  # returns a distinct array of timeline_event_types of all timeline entries posted in the current stage
  def current_stage_event_types
    TimelineEventType.find(current_stage_events.pluck(:timeline_event_type_id).uniq)
  end

  def current_stage
    changed_stage_event = latest_change_of_stage
    changed_stage_event ? changed_stage_event.timeline_event_type.key : TimelineEventType::TYPE_STAGE_IDEA
  end

  # Returns current iteration, counting end-of-iteration events. If at_event is supplied, it calculates iteration during
  # that event.
  def iteration(at_event: nil)
    if at_event
      timeline_events.where('created_at < ?', at_event.created_at)
    else
      timeline_events
    end.end_of_iteration_events.verified.count + 1
  end

  def timeline_verified?
    approved? && timeline_events.verified.present?
  end

  def admin?(user)
    admin == user
  end

  def timeline_events_for_display(viewer)
    if viewer && self == viewer.startup
      timeline_events.order(:event_on, :updated_at).reverse_order
    else
      timeline_events.verified.order(:event_on, :updated_at).reverse_order
    end
  end

  after_save do
    if approval_status_changed? && approved? && timeline_events.blank?
      prepopulate_timeline!
    end
  end

  def prepopulate_timeline!
    create_default_event %w(team_formed new_product_deck one_liner)
  end

  def create_default_event(types)
    types.each do |type|
      timeline_events.create(
        user: admin,
        timeline_event_type: TimelineEventType.find_by(key: type),
        auto_populated: true,
        verified_at: Time.now,
        event_on: Time.now
      )
    end
  end

  # Update stage whenever startup is updated. Note that this is also triggered from TimelineEvent after_commit.
  after_save :update_stage!

  # Update stage stored in database. Do not trigger callbacks, to avoid callback loop.
  def update_stage!
    update_column(:stage, current_stage)
  end

  def latest_help_wanted
    timeline_events.verified.help_wanted.order(created_at: 'desc').first
  end

  def display_name
    label = product_name
    label += " (#{name})" if name.present?
    label
  end

  def self.available_batches
    Batch.where(id: Startup.batched.pluck(:batch_id).uniq)
  end

  def self.leaderboard_of_batch(batch)
    startups_by_points = Startup.not_dropped_out.where(batch: batch)
      .joins(:karma_points)
      .where('karma_points.created_at > ?', leaderboard_start_date)
      .where('karma_points.created_at < ?', leaderboard_end_date)
      .group(:startup_id)
      .sum(:points)
      .sort_by { |_startup_id, points| points }.reverse

    last_points = nil
    last_rank = nil

    startups_by_points.each_with_index.map do |startup_points, index|
      startup_id, points = startup_points

      if last_points == points
        rank = last_rank
      else
        rank = index + 1
        last_rank = rank
      end

      last_points = points

      [startup_id, rank]
    end
  end

  def self.leaderboard_toppers_for_batch(batch, count: 3)
    # returns ids of n toppers on the leaderboard
    leaderboard_of_batch(batch)[0..count - 1].map { |id_and_rank| id_and_rank[0] }
  end

  def self.without_karma_and_rank_for_batch(batch)
    ranked_startup_ids = Startup.not_dropped_out.where(batch: batch)
      .joins(:karma_points)
      .where('karma_points.created_at > ?', leaderboard_start_date)
      .where('karma_points.created_at < ?', leaderboard_end_date)
      .pluck(:startup_id).uniq

    unranked_startups = Startup.not_dropped_out.where(batch: batch)
      .where.not(id: ranked_startup_ids)

    [unranked_startups, ranked_startup_ids.count + 1]
  end

  # Starts on the week before last's Monday 6 PM IST.
  def self.leaderboard_start_date
    if monday? && before_evening?
      8.days.ago.beginning_of_week
    else
      7.days.ago.beginning_of_week
    end.in_time_zone('Asia/Calcutta') + 18.hours
  end

  # Ends on last week's Monday 6 PM IST.
  def self.leaderboard_end_date
    if monday? && before_evening?
      8.days.ago.end_of_week
    else
      7.days.ago.end_of_week
    end.in_time_zone('Asia/Calcutta') + 18.hours
  end

  class << self
    private

    def monday?
      Date.today.in_time_zone('Asia/Calcutta').wday == 1
    end

    def before_evening?
      Time.now.in_time_zone('Asia/Calcutta').hour < 18
    end
  end
end

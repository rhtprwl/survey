# == Schema Information
#
#
# Table name: users
#
#  id                     :integer         not null, primary key
#  username               :string          not null
#  email                  :string          not null
#  created_at             :datetime        not null
#  updated_at             :datetime        not null
#  password_digest        :string          not null
#  admin                  :boolean         default("f"), not null
#  remember_digest        :string
#  password_reset_token   :string
#  password_reset_sent_at :datetime
#  sensitivity            :integer         not null
#  forename               :string
#  surname                :string
#  middlename             :string
#  description            :text
#  url_facebook           :string
#  url_linkedin           :string
#  url_homepage           :string
#  url_twitter            :string
#  url_google_plus        :string
#  visibility             :integer
#  gender                 :integer
#  title                  :string
#  company                :string
#  location               :string
#  mononym                :string
#

class User < ActiveRecord::Base
  include Authenticatable
  include Activable
  include SuperModel
  include Humane
  include SearchParty
  include Rubix
  include NunCheck
  require 'factory_girl'

  PER_PAGE = 20
  paginates_per PER_PAGE

  MIN_SENSITIVITY = 1
  MAX_SENSITIVITY = 10

  # contacts
  has_many :contacts, foreign_key: :owner_id, dependent: :destroy
  handles_subclasses_of :contacts

  has_many :counsels_authored,
      dependent: :destroy,
      foreign_key: :sender_id,
      class_name: 'Counsel'
  alias authored_counsels counsels_authored

  has_many :counsels_received,
      foreign_key: :recipient_id,
      class_name: 'Counsel'
  alias received_counsels counsels_received

  has_many :invites_received,
    foreign_key: :recipient_id,
    class_name: 'UserInvite'
  alias received_invites invites_received

  has_many :solicitations, foreign_key: :sender_id
  alias solicitations_authored solicitations
  alias authored_solicitations solicitations_authored

  has_many :user_listed_surveys
  has_many :listed_surveys,
    through: :user_listed_surveys,
    source: :survey,
    dependent: :destroy

  has_many :user_favorite_surveys
  has_many :favorite_surveys,
    through: :user_favorite_surveys,
    source: :survey,
    dependent: :destroy

  has_many :comments

  has_many :surveys_authored,
    foreign_key: :owner_id,
    class_name: 'Survey'
  alias authored_surveys surveys_authored

  # survey aggregators
  # nb: not every SurveyAggregator belongs_to a user
  has_many :survey_aggregators, dependent: :destroy

  validate :username_is_valid
  RESERVED_USERNAMES_FILE = 'config/reserved_usernames.txt'

  validates :forename, length: { maximum: 50 }
  validates_presence_of :forename, unless: :mononym

  validates :middlename, length: { maximum: 50 }

  validates :surname, length: { maximum: 50 }
  validates_presence_of :surname, unless: :mononym

  validates :email,
      presence: true,
      format: { with: Email::VALID_EMAIL_REGEX },
      uniqueness: { case_sensitive: false }

  validates_inclusion_of :sensitivity,
    in: MIN_SENSITIVITY..MAX_SENSITIVITY

  validates_presence_of :authenticator

  validate :validate_old_password,
    if: %w(password_digest_changed? @skip_old_password_validation.nil?),
    on: :update

  after_initialize :set_authenticator, if: :new_record?

  alias_attribute :lastname, :surname
  alias_attribute :firstname, :forename

  # custom attribute for old password verification
  attr_accessor :old_password

  #########################################################################################
  # void skip_old_password_validation()
  # Skip :validate_old_password validation
  # returns: void
  #########################################################################################
  def skip_old_password_validation
    @skip_old_password_validation = true
  end

  #########################################################################################
  # Symbol visibility()
  # Get the visibility for this user profile. Only public is supported for now.
  # returns: (:public || :private)
  #########################################################################################
  def visibility
    return :public
  end

  #########################################################################################
  # String forename()
  # Get the user's first name. If this is a mononym user, return that; otherwise forename.
  # returns: user's first name
  #########################################################################################
  def forename
    mononym || read_attribute(:forename)
  end

  #########################################################################################
  # String about()
  # Get the (user-defined) description of this user (i.e., 'About Me').
  # returns: user's first name
  #########################################################################################
  def about
    self.description
  end

  #########################################################################################
  # String displayname()
  # Get the default displayname (i.e., the full name) of this user.
  # returns: user's full name
  #########################################################################################
  def displayname
    mononym || [forename, middlename, surname].join_unless_nil(' ')
  end
  alias :name :displayname
  alias :fullname :displayname
  alias :to_s :displayname

  #########################################################################################
  # String shortname()
  # Get a short version of this user's name for use in tight spaces.
  # returns: a short name for the user
  #########################################################################################
  def shortname
    mononym || forename
  end

  #########################################################################################
  # String reversed_name()
  # Get the comma-separated lastname-first version of this user's name (e.g.
  # Jones-Smith, Kate).
  # returns: the user's name, last name first
  #########################################################################################
  def reversed_name
    mononym || "#{surname}, #{forename}" +
      (self.has_a?(:middle_name) ? " #{middlename}" : "")
  end

  #########################################################################################
  # String title_and_company()
  # Get the title and company string for this user (e.g. 'Manager, Acme Global
  # Corp.'), if defined.
  # returns: the title and company || nil
  #########################################################################################
  def title_and_company
    [self.title, self.company].join(", ") if (self.title && self.company)
  end

  #########################################################################################
  # Boolean has_favorite?( survey )
  # Does this user have the given survey as a favorite?
  # returns: Boolean
  #########################################################################################
  def has_favorite? survey
    UserFavoriteSurvey.where( survey: survey, user: self ).present?
  end

  #########################################################################################
  # Boolean has_listed?( survey )
  # Does this user have the given survey as a listed survey?
  # returns: Boolean
  #########################################################################################
  def has_listed? survey
    UserListedSurvey.where( survey: survey, user: self ).present?
  end

  #########################################################################################
  # Boolean owns?( resource )
  # Is this user the owner of the given resource?
  # returns: Boolean
  #########################################################################################
  def owns? resource
    resource.owner == self
  end

  #########################################################################################
  # Boolean has_contact?( User || Email )
  # Does this user have the given User or Email as a contact?
  # returns: Boolean
  # TODO: refactor User and Email into Person
  #########################################################################################
  def has_contact? contact
    case contact
    when User
      UserContact.where(owner_id: self.id, user_id: contact.id).present?
    when Email
      EmailContact.where(owner_id: self.id, email: contact.email).present?
    end
  end

  #########################################################################################
  # void add_contact( User || Email )
  # Add the given User or Email as a contact.
  # returns: nothing
  #########################################################################################
  def add_contact(contact)
    case contact
    when User
      return UserContact.create(owner_id: self.id, user_id: contact.id)
    when Email
      return EmailContact.create(owner_id: self.id, email: contact.email)
    end
  end

  #########################################################################################
  # void add_contacts( Array<contacts> )
  # Add a list of (User|Email) objects as contacts.
  # returns: nothing
  #########################################################################################
  def add_contacts(contacts)
    contacts.each { |c| add_contact(c) } unless contacts.nil?
  end

  #########################################################################################
  # void remove_contact( User | Email )
  # Remove the given User or Email from the contacts list.
  # returns: nothing
  #########################################################################################
  def remove_contact(contact)
    case contact
    when User
      UserContact.destroy self.user_contacts.where(user_id: contact.id)
    when Email
      EmailContact.destroy self.email_contacts.where(email: contact.email)
    end
  end

  #########################################################################################
  # Array<Solicitations> draft_solicitations()
  # Get all draft solicitations for this user.
  # returns: ActiveRecordRelation of solicitations
  #########################################################################################
  def draft_solicitations
    Solicitation.where sender: self, draft: true
  end

  #########################################################################################
  # String image_url( size: size )
  # Get a url for the image for this user.
  # returns: a url
  #########################################################################################
  def image_url size: 80
    omniauth_image_url( size: size ) || gravatar_image_url( size: size )
  end
  alias :image :image_url
  alias :image_path :image_url

  #########################################################################################
  # Array<Symbol> social_sites()
  # Return a list of the social media sites for which this user has a url defined.
  # returns: Array<Symbol>
  #########################################################################################
  def social_sites
    User.social_site_attributes_keys.keep_if { |key| not self.send(key).nil? }
  end

  #########################################################################################
  # JSON as_indexed_json( args= {} )
  # Return the Elasticsearch JSON hash of searchable model fields.
  # returns: JSON
  #########################################################################################
  def as_indexed_json(args = {})
    raise 'oops. time to figure this as_indexed_json thing out' if args != {}
    self.as_json({
        only: [:username, :forename, :surname, :middlename, :email],
    })
  end

  #########################################################################################
  # void assign_social_site( name, url )
  # Assign the given social site (.e.g. 'LinkedIn', 'www.linkedin.com/users/12345') to the
  # correct model attribute.
  # returns: nothing
  #########################################################################################
  def assign_social_site name, url
    User.social_site_attributes_keys.each do |key|
      if key.to_s[/#{name}/i]
        self[key] = url
      end
    end
  end

  #########################################################################################
  # boolean google_user?()
  # Is this user authenticated by Google? (If so, she can't log in with a password.)
  # returns: boolean
  #########################################################################################
  def google_user?
    authenticated_by? User::Authenticator::GOOGLE
  end

  #########################################################################################
  # boolean omniauth_user?()
  # Is this user authenticated by Omniauth? (If so, she can't log in with a password.)
  # returns: boolean
  #########################################################################################
  def omniauth_user?
    not authenticated_by? User::Authenticator::LOCAL
  end

  #########################################################################################
  # String omniauth_provider()
  # Provide a user-friendly string for this user's omniauth provider.
  # raises: StandardError, if user is not authenticated by omniauth
  # returns: a view-friendly omniauth provider string
  #########################################################################################
  def omniauth_provider
    raise 'user is not authenticated by omniauth' unless omniauth_user?
    Authenticator.friendly_string_for self.authenticator
  end

  private

  #########################################################################################
  # void validate_old_password()
  # Validate that the provided 'old password' is the correct one (during a password
  # change.)
  # returns: nil
  #########################################################################################
  def validate_old_password
    unless BCrypt::Password.new(password_digest_was) == old_password
      errors.add(:old_password, 'Your old password was incorrect.')
    end
  end

  #########################################################################################
  # void username_is_valid()
  # Validate that the username passes all the checks in username_available? We include all
  # validation checks in `username_available?` (rather than in standard Rails validations)
  # so that we can easily call them from the controller to check a username before
  # actually attempting to create a user.
  # returns: nil
  #########################################################################################
  def username_is_valid
    unless User.username_available? username, user: self
     errors.add(:username, "Username '#{username}' is not available.")
    end
  end

  #########################################################################################
  # String gravatar_image_url( size: 80 )
  # Return the gravatar image url for this user's email address (or a default icon).
  # returns: a url
  #########################################################################################
  def gravatar_image_url size: 80
    return nil unless self.has_a? :email
    md5 = OpenSSL::Digest::MD5.new self.email.downcase.strip
    # default = 'retro' # see http://en.gravatar.com/site/implement/images/
    default = 'identicon' # see http://en.gravatar.com/site/implement/images/
    "https://www.gravatar.com/avatar/#{md5}?s=#{size}&d=#{default}"
  end

  #########################################################################################
  # String omniauth_image_url( size: size )
  # Return the :image_url (which must be a google image) appended with the size parameter.
  # For now, we only support Google, so there is no ambiguity about the size parameter
  # string.
  # returns: a url
  #########################################################################################
  def omniauth_image_url size: 80
    url = self.read_attribute :image_url
    url ? "#{url}?sz=#{size}" : nil
  end

  #########################################################################################
  # boolean authenticated_by?( int id )
  # Is this user authenticated by the given authenticator (e.g.,
  # User::Authenticator::GOOGLE or User::Authenticator::LOCAL)?
  # returns: boolean
  #########################################################################################
  def authenticated_by? authenticator_id
    self.authenticator == authenticator_id
  end

  #########################################################################################
  # void set_authenticator()
  # Set the authenticator at model creation. Defaults to Authenticator::LOCAL unless it
  # has already been set. Also sets a random password for an Omniauth user (who will never
  # see it); this is required by has_secure_password.
  # returns: void
  #########################################################################################
  def set_authenticator
    self.authenticator ||= User::Authenticator::LOCAL

    # Set a random password if none exists. This should only be the case for an
    # unpersisted Omniauth user.
    self.password_digest ||= SecureRandom.base64
  end

  class << self

    #########################################################################################
    # User find_by_email_or_username( String email_or_username )
    # Find a user by either email or username (both of which are guaranteed to be unique.)
    # returns: a user, or nil if not found
    #########################################################################################
    def find_by_email_or_username email_or_username
      find_by_email(email_or_username) || find_by_username(email_or_username)
    end

    #########################################################################################
    # User find_by_id( *args )
    # Trick the model into returning the missing_user() when the original id is no longer found.
    # returns: a user
    #########################################################################################
    def find_by_id *args
      super( *args )
    rescue ActiveRecord::RecordNotFound
      return User.missing_user
    end

    #########################################################################################
    # User authenticate( email_or_username, password )
    # Look up this user by unique key (email or username) and try the password.
    # returns: user, or nil if the user is not found or has the wrong password
    #########################################################################################
    def authenticate email_or_username, password
      user = find_by_email_or_username email_or_username
      (user && user.authenticate(password) ? user : nil)
    end

    #########################################################################################
    # User from_omniauth( auth_hash )
    # Look up this user by the email in the auth_hash. If the user exists, return her.
    # Otherwise, new up a (non-persisted) user using the information in the auth_hash.
    # returns: an existing or new (unpersisted) user
    #########################################################################################
    def from_omniauth auth
      user = User.find_by_email auth['info']['email']
      return user if user

      # Omniauth users require a random password for compatibility with
      # has_secure_password. In theory, the user should never know or be able to use this
      # password. In practice, this may happen, but there's no real concern if it does.
      # Note that Omniauth users will receive a new password via the set_authenticator()
      # method at creation time, but we set it here so that the new user is valid.
      random_password = SecureRandom.base64

      user = User.new \
        email:           auth['info']['email'],
        username:        best_guess_username(auth),
        forename:        auth['info']['first_name'],
        surname:         auth['info']['last_name'],
        gender:          User::Gender.id_for_auth(auth),
        sensitivity:     5,
        image_url:       auth['info']['image'],
        location:        auth['info']['location'],
        authenticator:   User::Authenticator::GOOGLE,
        password_digest: random_password

      auth['info']['urls'].each do |name, url|
        user.assign_social_site name, url
      end if auth['info']['urls']

      user
    end

    #########################################################################################
    # Array<String> social_sites_attributes_keys()
    # Get a list of all the keys for social sites attributes on this class; i.e.,
    # :url_facebook, :url_google_plus, :url_linkedin, etc.
    # returns: a list of social site attribute keys
    #########################################################################################
    def social_site_attributes_keys
      column_names.grep(/url_/)
    end

    #########################################################################################
    # boolean username_available?( username, user: nil )
    # Does the username meet all requirement for a valid new username? This includes:
    #   * existence and length
    #   * uniqueness
    #   * non-profanity
    #   * absence in the reserved usernames list
    # If the `user` argument is provided, then the user's username is considered valid; if
    # not, then the username is invalid if any user already has it (case-insensitively).
    # returns: boolean
    #########################################################################################
    def username_available? username, user: nil

      # reject empty usernames
      return false if username.nil? or username.empty?

      # enforce character cound between 3 and 50
      return false unless (3..50).include? username.chars.count

      # reject usernames containing profanity
      return false if contains_profanity? username

      # reject reserved usernames
      return false if Textify.readlines(RESERVED_USERNAMES_FILE).include? username

      # check if another user already has this case-insensitive username
      existing_user = User.find_by("LOWER(username)=?", username.downcase)
      return false unless existing_user.nil? or existing_user == user

      true
    end

    #########################################################################################
    # DEPRECATED
    # User test_user()
    # Return the one and only test user, for testing purposes. Don't use this;
    # really the user model should not know about this special user.
    # returns: User
    #########################################################################################
    def test_user
      User.find_by_username('test_user') || FactoryGirl.create(:test_user)
    end

    #########################################################################################
    # User missing_user()
    # Return a mocked-up (non-persisted) user for use when the original user is
    # missing. This may occur frequently and is not necessarily an error; for
    # instance, if a user creates a survey and then deletes her account, the
    # survey should still stick around and belong now to the missing_user.
    # Note: not sure what the best way to handle this is.
    # returns: the "missing user"
    #########################################################################################
    def missing_user
      User.new \
        forename: App::NAME,
        surname: '',
        username: App::NAME,
        email: "#{App::NAME}@#{App::EMAIL_DOMAIN}".downcase,
        password: "",
        password_confirmation: "",
        sensitivity: 10
    end

    #########################################################################################
    # User anonymous_user()
    # Return a mocked-up (non-persisted) user for use when the original user wants to be
    # anonymous; i.e., this user can be displayed in views without betraying the identity
    # of the original user.
    # returns: the "anonymous user"
    #########################################################################################
    def anonymous_user
      User.new \
        mononym: 'Anonymous',
        username: 'anonymous',
        email: "anonymous@#{App::EMAIL_DOMAIN}".downcase,
        password: "",
        password_confirmation: "",
        sensitivity: 10
    end

    private

    #########################################################################################
    # String best_guess_username( auth_hash )
    # Guess a decent username for this (new) user, based on various values in the auth_hash.
    # TODO move me to a module somewhere (?)
    # returns: a suggested username
    #########################################################################################
    def best_guess_username auth

      [ (auth['info']['nickname'] rescue nil),
        auth['info']['email'].split('@')[0],
        (auth['info']['urls']['Google'].split('+')[1] rescue nil),
      ].compact.each do |username|
        return username unless User.exists?( username: username )
      end

      username = auth['info']['email'].split('@')[0]
      loop.with_index do |_, i|
        username = "#{username}#{i + 1}"
        return username unless User.exists?( username: username )
      end

      return username
    end

  end # class << self

  #########################################################################################
  #########################################################################################
  # class User::Authenticator
  # A simple class for keeping track of how this user is authenticated to the app; for
  # now, just via Google or a local password.
  #########################################################################################
  class Authenticator
    LOCAL  = 0
    GOOGLE = 1

    #########################################################################################
    # String friendly_string_for( id )
    # Get a view-friendly string for this authenticator_id.
    # returns: view-friendly authenticator string
    #########################################################################################
    def self.friendly_string_for authenticator_id
      Hash[
        constants.collect do |constant|
          [const_get(constant), constant.to_s.titlecase]
        end
      ][authenticator_id]
    end
  end
  #########################################################################################
  #########################################################################################

  #########################################################################################
  #########################################################################################
  # class User::Gender
  # A simple class for keeping track of a user's gender, whatever that is these days.
  #########################################################################################
  class Gender
    UNKNOWN       = 0
    FEMALE        = 1
    MALE          = 2
    TRANSGENDERED = 3
    OTHER         = 4

    #########################################################################################
    # int Gender.id_for( string )
    # Get the gender id (databased-stored attribute) for a string like 'male' or 'female'.
    # returns: gender id
    #########################################################################################
    def self.id_for string
      string ||= 'UNKNOWN' # in case of nil string
      if constants.include? string.upcase.to_sym
        return const_get(string.upcase.to_sym)
      else
        return const_get(:UNKNOWN)
      end
    end

    #########################################################################################
    # int Gender.id_for( string )
    # Get the gender id for an auth hash.
    # returns: gender id
    #########################################################################################
    def self.id_for_auth auth
      self.id_for( (auth['extra']['raw_info']['gender'] rescue 'UNKNOWN') )
    end

  end # class Gender
  #########################################################################################
  #########################################################################################

  MISSING = User.missing_user
  ANONYMOUS = User.anonymous_user

end

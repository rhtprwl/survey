# == Schema Information
#
# Table name: surveys
#
#  id              :integer         not null, primary key
#  category_id     :integer         not null
#  title           :string          not null
#  owner_id        :integer         not null
#  created_at      :datetime        not null
#  updated_at      :datetime        not null
#  description     :text
#  responses_count :integer         default("0"), not null
#  instructions    :text
#  draft           :boolean         not null
#   post_id         :integer
#  private         :boolean         default("f"), not null
#

class Survey < ActiveRecord::Base
  include SuperModel
  include Draftable
  include DeepClone
  include Categorizable
  clones_dependents :questions, :page_breaks

  handles :_new_question

  include SearchParty

  DEFAULT_TITLE = "Untitled Survey"
  TITLE_MIN_CHARS = 8
  DESCRIPTION_MIN_CHARS = 20
  PER_PAGE = 10
  paginates_per PER_PAGE

  belongs_to :post
  validates_uniqueness_of :post_id, allow_nil: true

  has_many :promulgations

  belongs_to :owner, class_name: 'User'
  has_many :solicitations
  has_many :responses
  has_many :listed_surveys
  has_many :favorite_surveys

  has_many :page_breaks, -> { order( index: :asc ) },
    foreign_key: 'survey_id', class_name: 'SurveyPageBreak'
  accepts_nested_attributes_for :page_breaks, allow_destroy: true

  has_many :survey_questions #, -> { order 'index DESC' }
  has_many :text_questions
  has_many :likert_questions
  has_many :multiple_choice_questions
  accepts_nested_attributes_for :survey_questions, allow_destroy: true
  before_destroy :destroy_questions

  has_many :tips
  accepts_nested_attributes_for :tips, :allow_destroy => true

  # what happens when a user quits after creating a survey?
  # need to think about that one. For now, keep the owner id
  # but allow it to refer to a missing user.
  validates_presence_of :owner_id
  # validates_associated :owner

  validates :description, presence: true, length: { minimum: DESCRIPTION_MIN_CHARS }, unless: :draft?
  validates :title,  presence: true, length: { minimum: TITLE_MIN_CHARS, maximum: 150 }
  validates :category_id,
    numericality: { greater_than_or_equal_to: 0, less_than: Category.all.count },
    unless: :draft?

  # allow this for now in order to create surveys in surveys/new
  # validates_format_of :title,
  #   without: /\A#{DEFAULT_TITLE}\z/,
  #   message: "cannot be \"#{DEFAULT_TITLE}\""

  # attr_reader :question_id_map

  #########################################################################################
  # ActiveRecord::Relation publick
  # Find only public surveys (that are not private.)
  # returns: ActiveRecord::Relation
  #########################################################################################
  scope :publick, -> { where(private: false) }

  #########################################################################################
  # ActiveRecord::Relation viewable_by(user)
  # Find only surveys that are viewable by the user.
  # If user is nil, returns only public surveys.
  # returns: ActiveRecord::Relation
  #########################################################################################
  scope :viewable_by, -> user do
    user ? where("private = 'f' OR owner_id = #{user.id}") : publick
  end

  #########################################################################################
  # ActiveRecord::Relation posted( bool=true)
  # Find only open (posted) surveys.
  # returns: ActiveRecord::Relation
  #########################################################################################
  scope :posted, -> posted=true do
    posted ? where.not( post_id: nil ) : publick.where( post_id: nil )
  end
  alias_scope :open, :posted

  #########################################################################################
  # ActiveRecord::Relation top( count )
  # Find the most popular surveys, by some criteria. Currently this is just the
  # responses_count.
  # returns: ActiveRecord::Relation
  #########################################################################################
  scope :top, -> count=30 do
    self.publick.limit(count).order(responses_count: :desc)
  end

  #########################################################################################
  # ActiveRecord::Relation related_to( count )
  # Find surveys related to a given survey, by some measure of relatedness.
  # # TODO - implement me
  # returns: ActiveRecord::Relation
  #########################################################################################
  scope :related_to, -> survey, user=nil do
    self.viewable_by(user).limit( rand(10) ).order('RANDOM()')
  end

  #########################################################################################
  # boolean private?()
  # Indicates whether this is a private survey, which is accessible only by its owner.
  # returns: boolean
  #########################################################################################
  def private?
    private
  end

  #########################################################################################
  # boolean posted?()
  # Indicates whether this is a posted (open) survey, which any user can fill out for
  # public aggregation of results.
  # returns: boolean
  # alias: open?
  #########################################################################################
  def posted?
    post.present?
  end
  alias open? posted?

  #########################################################################################
  # Post create_post()
  # Create the singleton post for this survey.
  # returns: Post
  # raises: RuntimeError, if a post already exists for this survey
  #########################################################################################
  def create_post
    raise RuntimeError.new( 'already posted' ) unless post_id.nil?
    self.post = Post.create( user: owner ); save
    post
  end

  #########################################################################################
  # SurveyAggregator public_aggregator
  # Return the public aggregator for this survey (of which there is only one). This is the
  # aggregtor for the posted survey, which any logged-in user can fill out. The public
  # aggregator will be created if it does not already exist.
  # raises: RuntimeError, if this survey is not posted
  # returns: SurveyAggregator
  #########################################################################################
  def public_aggregator
    raise RuntimeError.new('unposted survey has no public aggregator') unless posted?
    SurveyAggregator.instance self, user: nil, public: true
  end

  #########################################################################################
  # SurveyAggregator aggregator_for_user( user )
  # Return the user aggregator for this survey and the given user (that is, an aggregator
  # for all responses to this survey sent to a particular user). The aggregator will be
  # created if it does not already exist.
  # returns: SurveyAggregator
  #########################################################################################
  def aggregator_for_user user
    SurveyAggregator.instance self, user: user, public: false
  end

  #########################################################################################
  # SurveyAggregator aggregator_for_attestation( counsel_or_promulgation )
  # Return an aggregator for this counsel or promulgation. If the counsel has no User
  # recipient (i.e., it's for an email address), there is no aggregator and this method
  # returns nil.
  # returns: SurveyAggregator or nil
  #########################################################################################
  def aggregator_for_attestation counsel_or_promulgation
    case counsel_or_promulgation
    when Counsel
      counsel = counsel_or_promulgation
      if counsel.recipient.is_a? User
        aggregator_for_user counsel.recipient
      else
        nil # counsel recipient is an email; no aggregator exists
      end
    when Promulgation
      public_aggregator
    end
  end

  #########################################################################################
  # SurveyAggregator aggregator_for( user_or_attestation )
  # Convenience method to find the aggregator relevant to this User, Counsel, or
  # Promulgation.
  # returns: SurveyAggregator
  #########################################################################################
  def aggregator_for user_or_attestation
    case user_or_attestation
    when User
      user = user_or_attestation
      aggregator_for_user user
    when Counsel, Promulgation
      attestation = user_or_attestation
      aggregator_for_attestation attestation
    end
  end

  #########################################################################################
  # boolean promulgated_by? user
  # Returns true if this user has already filled out this (open) survey.
  # raises: RuntimeError, if this survey is not posted
  # returns: boolean
  #########################################################################################
  def promulgated_by? user
    raise RuntimeError.new('unposted survey has no promulgations') unless posted?
    not promulgated_at( by: user ).nil?
  end

  #########################################################################################
  # DateTime promulgated_at( by: user )
  # Returns the date at which the given user answered the questions in this survey
  # publicly, or nil if no such answer exists.
  # raises: RuntimeError, if this survey is not posted
  # returns: DateTime || nil
  #########################################################################################
  def promulgated_at by: user
    raise RuntimeError.new('unposted survey has no promulgations') unless posted?
    Promulgation.find_by( user: by, survey: self ).try :created_at
  end

  #########################################################################################
  # User owner()
  # Get the owner (user) of this survey. If the user has deleted his or her account, thus
  # orphaning this survey, then return the User.missing_user.
  # returns: User
  #########################################################################################
  def owner
    User.find(owner_id)
  rescue ActiveRecord::RecordNotFound
    User.missing_user
  end

  #########################################################################################
  # Integer questions_count()
  # Get the number of questions in this survey.
  # returns: the number of questions
  #########################################################################################
  def questions_count
    self.questions.count
  end

  #########################################################################################
  # Array<Question> questions()
  # Get the questions for this survey.
  # returns: an array of Questions
  # TODO - cache this? Need to be careful about invalidating it.
  #########################################################################################
  def questions
    return nil unless self.id?
    SurveyQuestion.subclasses.collect do |table|
      table.where(survey: self)
    end.compact.flatten.sort_by(&:sort_index)
  end

  #########################################################################################
  # void questions_attributes=( attributes )
  # Accept nested attributes for the questions in this survey. This method works by
  # completely destroying all existing questions (which is ok since they belong_to this
  # survey alone) and recreating them based on the passed attributes (which presumably
  # reflect the current state of the DOM). This is much easier (at least, in the absence
  # of a relevant JS framework), than trying to match the DOM questions to the Questions
  # in the DB, since they may have changed order, question_type, and content.
  # returns: nothing
  #########################################################################################
  def questions_attributes=(attributes)
    destroy_questions
    attributes.each_with_index do |(_key, attrs), index|
      next if attrs['_ignore'] == 'true'
      next if attrs['_destroy'] == 'true'

      ignored_keys = ['id', 'ajax_id', '_ignore', '_destroy', 'type', 'new_index', 'index']

      klass = attrs['type'].classify.constantize
      klass.create survey: self,
        index: index + 1,
        **attrs.except(*ignored_keys).deep_symbolize_keys
    end
  end
  alias questions= questions_attributes=

  #########################################################################################
  # void page_breaks_attributes=( attributes )
  # Accept nested attributes for the page breaks in this survey. Like
  # questions_attributes=(), this method works by completely destroying all existing
  # page breaks (which is ok since they belong_to this survey alone) and recreating them
  # based on the passed attributes.
  # returns: nothing
  #########################################################################################
  def page_breaks_attributes=(attributes)
    self.page_breaks.destroy_all
    attributes.each do |_key, attrs|
      next if attrs['_ignore'] == 'true'
      next if attrs['_destroy'] == 'true'
      self.insert_page_break \
        title: attrs['title'],
        description: attrs['description'],
        before: attrs['index']
    end
  end

  #########################################################################################
  # void tips_attributes=()
  # Accept nested attributes for the tips associated with 1) questions in this survey and
  # 2) either a Counsel or a Promulgation.
  # returns: nothing
  #########################################################################################
  def tips_attributes=(attributes) # when filling out survey
    unless attributes[:counsel_id] or attributes[:promulgation_id]
      raise ActiveRecord::AttributeAssignmentError,
        "missing required attribute counsel_id or promulgation_id: #{tips_attributes}"
    end

    counsel = Counsel.find_by id: attributes.delete(:counsel_id)
    promulgation = Promulgation.find_by id: attributes.delete(:promulgation_id)

    # an aggregator must be initialized *prior* to creating the first tip for it
    # TODO - this sucks, but I don't see a way out of it except requiring the user to call
    # aggregator.reload explictly after creating it, which also sucks.
    self.aggregator_for(counsel || promulgation).try :init

    attributes.each do |uid, content|
      question = Eunuch::ID.find(uid)
      Tip.create \
        question: question,
        question_type: question.type,
        counsel_id: (counsel.id if counsel),
        promulgation_id: (promulgation.id if promulgation),
        content: content
    end
  end

  #########################################################################################
  # Integer ranking()
  # Return the ranking (e.g. survey 33 out of 692) of this survey, in terms of its
  # popularity.
  # returns: integer
  # TODO
  #########################################################################################
  def ranking
    (1..Survey.count).to_a.sample
  end

  #########################################################################################
  # void deprecate( new survey )
  # Deprecated this survey in favor of a new (updated) version. NOT YET IMPLEMENTED.
  # popularity.
  # returns: integer
  #########################################################################################
  def deprecate new_survey
    :reserved
  end

  #########################################################################################
  # void used?()
  # Has this survey ever actually been sent to anyone, or filled out?
  # returns: nothing
  #########################################################################################
  def used?
    return true unless Counsel.where(survey: self).empty?
    return true unless Solicitation.where(survey: self).empty?
    return true unless Promulgation.for_survey(self).empty?
    return false
  end

  #########################################################################################
  # Array<Survey> related_surveys()
  # Get other surveys related to this one. NOT YET IMPLEMENTED.
  # returns: an array of surveys
  # TODO
  #########################################################################################
  def related_surveys
    Survey.where.not(draft: true).sample(20)
  end

  #########################################################################################
  # SurveyPageBreak insert_page_break( title:, description:, before: )
  # Insert a page break at the position given by 'before' argument. That is, if 'before'
  # == 3, is, the page break should appear just before the question with index #3
  # (one-indexed). Note that a page_break might be given a value of `before` which is
  # greater than the total number of questions, in which case the page_break should appear
  # at the end of the survey (and have no questions on the page). If multiple
  # page breaks are inserted before the same question, their order is not
  # guaranteed; all but the last one of them will be empty (have no questions),
  # but will still be valid pages.
  # returns: the new SurveyPageBreak
  #########################################################################################
  def insert_page_break title:, description:, before:
    SurveyPageBreak.create \
      survey: self,
      title: title,
      description: description,
      index: before
  end

  #########################################################################################
  # Array items()
  # Get the questions and page breaks for this survey in a one-dimensional (flat) list.
  # Don't use this to get figure out the pages of the survey; use pages() instead.
  # called by: surveys/edit, which does not divide the survey into separate pages
  # returns: boolean
  #########################################################################################
  def items
    page_breaks.reverse.inject(questions) do |_items, page_break|
      # insert page breaks from the end first to keep indices valid
      item_index = page_break.index - 1 # one-indexed
      _items.insert item_index, page_break
    end
  end

  #########################################################################################
  # Boolean blank?()
  # Is this survey lacking any actual content? (For instance, if it's just been created
  # for use in the DOM.)
  # returns: boolean
  #########################################################################################
  def blank?
    if title.present? and title != Survey::DEFAULT_TITLE
      return false
    end

    [:description, :instructions].each do |attr|
      return false if self.send(attr).present?
    end

    questions.each do |question|
      return false unless question.blank?
    end

    true
  end

  #########################################################################################
  # Boolean sendable?()
  # Is this survey sendable attached to a counsel? Yes, if at least one question has been
  # answered.
  # returns: boolean
  #########################################################################################
  def sendable?(counsel) # must have at least one question answered
    Tip.where(counsel: counsel).count > 0
  end

  #########################################################################################
  # JSON as_indexed_json( args = {} )
  # Return a JSON object required by Elasticsearch indicating the indexed fields of this
  # survey.
  # returns: JSON
  #########################################################################################
  # elasticsearch indices
  def as_indexed_json(args = {})
    raise 'oops. time to figure this as_indexed_json thing out' if args != {}
    self.as_json({
      only: [:title, :description],
      include: {
        owner: { only: :username },
        # questions: { only: title },
      }
    })
  end

  #########################################################################################
  # String to_s()
  # Return a user-friendly string representation of this survey.
  # returns: String
  #########################################################################################
  def to_s
    string = (id.nil? ? "unsaved survey" : "survey #{id}")
    string += " [#{self.questions_count} " +
      'question'.pluralize(self.questions_count) + "]: '#{title}'"
  end

  #########################################################################################
  # void increment_responses_count
  # Increment the responses_count, presumably after sending a Counsel or Promulgation with
  # this survey attached.
  # returns: nothing
  #########################################################################################
  def increment_responses_count
    self.responses_count += 1
    save
  end

  #########################################################################################
  # Integer invites_count
  # Return the number of times this survey has been sent with an invitation.
  # returns: a count of invites with this survey attached
  #########################################################################################
  def invites_count
    Invite.with_survey(self).count
  end

  #########################################################################################
  # Survey dup
  # Override dup method to make sure post_id is not copied.
  # returns: a duplicate Survey object
  #########################################################################################
  def dup
    return super unless post_id
    clone = super
    clone.post_id = nil
    clone
  end

  #########################################################################################
  # Survey::Page page( num )
  # Get the page numbered `num`.
  # returns: Survey::Page object
  #########################################################################################
  def page num
    raise ArgumentError.new 'Survey pages are one-indexed' if num < 1
    pages[num - 1]
  end

  #########################################################################################
  # Integer page_count
  # Get the total number of pages in this survey. (Some pages may be blank.)
  # returns: the page count
  #########################################################################################
  def page_count; pages.count; end
  alias pages_count page_count

  #########################################################################################
  # Array<Page> pages
  # Get an array of Survey::Page objects representing the pages in this survey.  The pages
  # are generated from the persisted SurveyPageBreaks in a non-trivial way; dealing with
  # page breaks at the beginning, end, and adjacent to each other gets a bit tricky. Note
  # that all questions are on a Survey::Page, even if there is no page break object
  # preceding them in the list.
  # returns: an array of Survey::Page objects
  #########################################################################################
  def pages
    page_breaks = SurveyPageBreak.where(survey: self).sort_by(&:index)

    has_no_page_breaks = page_breaks.empty?
    if has_no_page_breaks
      single_page = Survey::Page.new(survey: self, number: 1, questions: self.questions)
      return [single_page]
    end

    has_implicit_first_page = (page_breaks.empty? or page_breaks.first.index != 1)
    if has_implicit_first_page # i.e., no page break before page 1
      fake_page_break = SurveyPageBreak.new(title: nil, description: nil, index: 1)
      page_breaks.insert 0, fake_page_break
    end

    pages_for_page_breaks page_breaks
  end

  class << self

    #########################################################################################
    # Survey draft_survey_for_user( User user )
    # Return a draft survey for this user, for use in the view.
    # KLUDGE ALERT This is necssary because we actually create new surveys in
    # the surveys/new method to get all the nested fields to work correctly in
    # the templates. Without code here to delete existing draft surveys, a new
    # survey is created every time you visit surveys/new. This should really be
    # refactored one day so that surveys/new doesn't create anything.
    # TODO
    # returns: a Survey
    #########################################################################################
    def draft_survey_for user
      user.authored_surveys.where(draft: true).destroy_all
      survey = user.authored_surveys.create \
        draft: true,
        title: Survey::DEFAULT_TITLE,
        category_id: Category[:miscellaneous].id
      survey.text_questions.create content: SurveyQuestion::DEFAULT_CONTENT

      # TODO - why is index hosed after record deletion?  Callbacks should be
      # taking care of this. Need to fix this.
      # Survey.reset_search wait: true
      # update 2015.11.13 - problem seems to have gone away. Keep tabs on this.
      # update 2015.11.21 - problem is back, but now at first line in this method.
      survey
    end

  end

  private

  #########################################################################################
  # Array<Page> pages_for_page_breaks( page_breaks )
  # Divide up the survey into pages based on the given page breaks. Helper for pages().
  # returns: an array of Survey::Page objects
  #########################################################################################
  def pages_for_page_breaks page_breaks
    page_breaks.collect.with_index do |page_break, page_num|
      # page_num zero-indexed here

      is_after_all_questions = page_break.index > questions_count
      if is_after_all_questions
        page_questions = []
      else
        first_question = page_break.index - 1 # one-indexed -> zero-indexed

        on_last_page = (page_num == page_breaks.count - 1)
        if on_last_page
          last_question = questions_count - 1
        else
          last_question = page_breaks[page_num + 1].index - 2
          # subtract one and convert to zero-indexed
        end

        if last_question < first_question
          page_questions = []
        else
          page_questions = self.questions[first_question..last_question]
        end
      end

      Survey::Page.new \
        survey: self,
        number: page_num + 1, # one-indexed
        title: page_break.title,
        description: page_break.description,
        questions: page_questions
    end
  end

  #########################################################################################
  # void destroy_questions()
  # dependent: :destroy does not seem to play well with abstract class Question
  # call this function instead to destroy this survey's questions
  # returns: nothing
  #########################################################################################
  def destroy_questions
    self.questions.each(&:destroy)
  end

  #########################################################################################
  # class Survey::Page
  # This class represents the information associated with a single page in a survey:
  #   - title (may be absent)
  #   - description (may be absent)
  #   - questions array (may be empty)
  #########################################################################################
  class Page
    include ActiveModel::Model
    attr_accessor :title, :description
    attr_accessor :questions
    attr_accessor :number
    attr_accessor :survey
    alias num number

    def untitled?; title.nil? or title.empty?; end
    def first?; number == 1; end
    def last?; number == survey.page_count; end
  end

end
